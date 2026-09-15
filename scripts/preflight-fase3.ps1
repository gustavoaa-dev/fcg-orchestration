# Preflight da gravacao do video da Fase 3 (FCG) -- ASCII puro, sem BOM.
# Roda em Windows PowerShell 5.1. EXIT=1 se QUALQUER checagem falhar (Chk acumula falhas e segue:
# o objetivo e ver o quadro inteiro numa execucao, nao parar na primeira).
#
# O que este script checa (na ordem):
#   P1  cluster: os 11 pods da plataforma Running/Ready + promtail no DaemonSet; os 4 PVCs Bound
#   P2  gateway: /api/jogos SEM token responde 401 (a API nem e alcancada)
#   P3  USUARIO DE DEMONSTRACAO: login com demo@fcg.local + a senha de FCG_DEMO_SENHA devolve 200;
#       se o login falhar, o preflight CRIA o usuario pelo gateway (POST /api/usuarios) e AVISA --
#       o bloco do Gateway do video faz login ANTES do cadastro, entao o usuario precisa existir
#       antes de apertar REC
#   P4  gateway COM token: GET /api/jogos responde 200
#   P5  Prometheus: o job fcg-apis com 3 alvos up (users-api, catalog-api, payments-api)
#   P6  Loki: /ready = ready (via proxy do kubectl, com -eq: um Loki que ainda nao esta pronto
#       responde 503 "ingester not ready: waiting for 15s after being ready" e o -match aprovaria)
#       e o rotulo app com log recente. O log DA FUNCAO e ATENCAO quando o rotulo ainda nao existe
#       (o rotulo so nasce depois que a funcao sobe uma vez na retencao de 24h). Quando o rotulo
#       existe a checagem busca LINHAS de verdade na janela de 24h (query_range com start/end em
#       epoch) e da [OK] so com linha lida: era tautologica (o Chk so existia no ramo em que o
#       predicado ja era verdadeiro, sem poder reprovar) -- achado I4 da revisao final.
#   P7  Grafana: /api/health ok, datasource Loki + Prometheus e os dashboards fcg-apis/fcg-logs
#   P8  KEDA: as tres filas notifications-* existem no broker e o ScaledObject esta Ready=True
#       (sem fila, o KEDA cai em TriggerError e a funcao SIMPLESMENTE NAO SOBE: falha silenciosa)
#   P9  DADOS DE DEMONSTRACAO: pelo menos 3 jogos no catalogo; se faltar, promove o usuario de
#       demonstracao a Admin (SQL por STDIN para /tmp do pod + "sqlcmd -i" -- NENHUMA aspas interna no
#       kubectl exec, que o PowerShell 5.1 entrega picado e o sqlcmd receberia truncado; a senha vem do
#       $SA_PASSWORD do ambiente do container) e CONFERE o Role lido do banco depois do UPDATE, porque
#       o login responde 200 com qualquer role e um UPDATE sem efeito so apareceria no POST de jogo.
#       Depois refaz o login, cria os jogos que faltam, le a biblioteca do usuario
#       (GET /api/biblioteca/{userId} -- o id dos itens vem no campo "gameId", medido no cluster) e
#       escolhe o JOGO DO BLOCO 4: o primeiro do catalogo que o usuario ainda NAO possui (o catalogo
#       volta ordenado por nome e a biblioteca cresce a cada rodada -- "o primeiro id do catalogo"
#       daria 400 na compra do video). Se todos os jogos do catalogo ja forem dele, o preflight CRIA
#       mais um jogo e REAVALIA a escolha; a checagem do bloco 4 e um predicado real (existe no
#       catalogo E nao esta na biblioteca lida). A checagem da biblioteca exige PARSE do corpo:
#       200 com corpo ilegivel (ParseOk = $false do Partir) REPROVA -- antes o corpo ilegivel virava
#       "lista vazia" e a escolha saia sem verificacao (falha ABERTA, achado I2 da revisao final);
#       so a lista vazia PARSEADA e "o usuario nao possui jogos"
#   P10 Redis com as chaves catalog:* e o Mongo respondendo (GET .../avaliacoes = 200)
#   P10b os comandos que SO aparecem no video sao exercitados aqui: as series dos paineis em
#       /metrics (proxy do kubectl, sem port-forward; o contador de pagamentos e lido DEPOIS da
#       compra, porque a familia com labels so nasce no primeiro evento consumido -- achado I1),
#       a compra de verificacao -- que usa OUTRO jogo, para nao consumir o do bloco 4, e so 202 e
#       [OK]: 400/409 sao re-execucao (ATENCAO, nao conta) e QUALQUER outro codigo (401/403/5xx/000)
#       REPROVA -- e o PUT/GET de avaliacao (upsert: 201 na 1a, 200 na 2a) no jogo do bloco 4
#   P11 FUNCAO EM 0 REPLICAS (estado inicial da demo), esperando o cooldown do KEDA se preciso
#
# CONTAGEM: "checagens" conta apenas PEDACOS QUE FORAM DE FATO VERIFICADOS. Os casos de ATENCAO
# (log da funcao ainda ausente no Loki; compra devolvendo 400/409 por posse -- que, sem evento novo
# nesta rodada, tambem deixa o contador de pagamentos sem prova e tira a checagem dele; biblioteca
# devolvendo 404 por ainda nao existir -- que tambem tira a checagem do jogo do bloco 4, porque sem a
# lista lida a posse nao pode ser verificada) sao VARIACAO LEGITIMA DE ESTADO: NAO emitem [OK] e NAO
# incrementam o contador. Todo o resto reprova -- generalizar "!= 202" ou "!= 200" para ATENCAO
# engoliria justamente os codigos que denunciam um endpoint quebrado. O total varia de 48 a 54: 51 no
# caminho ideal; +3 se o preflight precisar promover o usuario a Admin (secret do sa, login apos a
# promocao e o Role lido do banco); -1 quando o rotulo da funcao ainda nao existe no Loki; -2 quando a
# biblioteca nao e lida (a checagem dela e a do jogo do bloco 4); -2 quando a compra de verificacao nao
# e aceita E o contador de pagamentos nao esta no /metrics (a segunda ATENCAO so aparece nesse caso:
# sem evento novo nao ha como provar a familia com labels).
#
# Nada de port-forward: o Prometheus e o Loki sao alcancados pelo proxy do kubectl
# (kubectl get --raw .../services/<svc>:<porta>/proxy/...) e o Grafana por kubectl exec + wget.
# Namespace: o proxy exige o namespace no caminho, entao os exec/get usam -n $namespace com o mesmo
# valor ($namespace = 'default') -- as duas metades olham para o mesmo lugar, sempre.
#
# SEGREDOS: a senha da demonstracao vem de $env:FCG_DEMO_SENHA (nao ha senha default no arquivo) e
# os valores de Secret do cluster sao decodificados em memoria. O unico lugar em que uma senha toca
# o disco e o corpo JSON temporario do login/cadastro, apagado no fim (bloco finally); toda saida
# passa por San(), que troca os segredos por *** antes de imprimir -- e a lista leva as DUAS formas da
# senha do Grafana (crua e URL-encoded), mesmo depois de o I3 ter tirado a senha do argv do kubectl exec.
# NENHUMA senha viaja como argumento de processo: a do sa e o $SA_PASSWORD do ambiente do container (SQL
# por stdin + "sqlcmd -i") e a do Grafana e o $GF_SECURITY_ADMIN_PASSWORD, expandido pelo shell de
# DENTRO do pod (antes ela ia embutida na URL do wget e aparecia no ps do host e do pod).
#
# Uso (preflight completo, uma execucao antes de gravar):
#   $env:FCG_DEMO_SENHA = '<senha>'; powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1
#
# GRAVACAO MODULAR (o video e gravado em 6 tomadas -- ver docs/roteiro-video-fase3.md):
#   powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo N     (N = 1..6)
#   Cada modulo VALIDA e PREPARA so o que a tomada dele precisa e termina em
#   "TUDO PRONTO PARA GRAVAR O MODULO N" (ou "PREFLIGHT REPROVADO ... NAO GRAVE ainda", como hoje).
#   O preparo e para ser rodado DE NOVO antes de cada retake: e ele que devolve o estado inicial
#   daquela tomada (o jogo livre novo da compra, a funcao em 0 replicas, as portas livres...).
#   Sem o parametro (-Modulo 0) o script e EXATAMENTE o de antes: as mesmas checagens e a mesma
#   linha TUDO PRONTO PARA GRAVAR. O bloco do modo por modulo fica depois dos helpers e SAI do
#   script quando termina, sem tocar em nenhuma linha do caminho completo.
#   Os modulos 1 e 6 nao fazem login e por isso nao exigem FCG_DEMO_SENHA; os modulos 2 a 5 exigem.
param(
    [string]$Gateway = 'http://localhost:8000',
    [string]$Email = 'demo@fcg.local',
    [string]$Nome = 'Jogador Demo',
    # SEM default: a senha da demonstracao NAO pode ficar versionada (regra global de segredos).
    [string]$Senha = $env:FCG_DEMO_SENHA,
    [int]$JogosMinimos = 3,
    [int]$EsperaCooldown = 180,
    # 0 (default) = preflight completo, comportamento original. 1..6 = preparo de UMA tomada.
    [ValidateRange(0, 6)][int]$Modulo = 0
)

$ErrorActionPreference = 'Continue'
$script:falhas = 0
$script:checagens = 0
$script:segredos = @()
# Namespace UNICO do script: o proxy do kubectl exige o namespace no proprio caminho
# (/api/v1/namespaces/<ns>/services/...), entao os exec/get usam -n $namespace com o MESMO valor --
# sem isso, metade das checagens olharia para o namespace do contexto e a outra metade para "default".
$namespace = 'default'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('fcg-preflight-' + [guid]::NewGuid().ToString('N'))

# Acumula a falha e segue.
function Chk($cond, $rotulo) {
    $script:checagens++
    $ok = [bool]$cond
    if (-not $ok) { $script:falhas++ }
    Write-Output ($rotulo + '=' + $ok + '  [' + $(if ($ok) { 'OK' } else { 'FALHOU' }) + ']')
}
function Step($m) { Write-Output ''; Write-Output ('=== ' + $m + ' ===') }
# Tira os segredos de qualquer texto antes de imprimir (a saida do kubectl exec do Grafana carrega
# a senha dentro da URL, e a do sqlcmd pode ecoar o comando).
function San($texto) {
    $s = [string]$texto
    foreach ($g in $script:segredos) {
        if ($g -and ([string]$g).Length -ge 4) { $s = $s.Replace([string]$g, '***') }
    }
    return $s
}
# O corpo vai por ARQUIVO (-d '@arquivo'): JSON inline perde as aspas no PowerShell.
function Body($nome, $json) {
    $p = Join-Path $tmp $nome
    Set-Content -Path $p -Value $json -Encoding Ascii -NoNewline
    return '@' + $p
}
# Separa o codigo HTTP do corpo (o -w '|%{http_code}' do curl poe os dois na mesma string).
# ParseOk = "HOUVE corpo e ele virou JSON" (nao apenas "o ConvertFrom-Json nao lancou"): corpo vazio e
# so espacos NAO contam como corpo -- medido no PowerShell 5.1, `'' | ConvertFrom-Json` e
# `'   ' | ConvertFrom-Json` NAO lancam nada e devolvem $null, entao sem essa checagem um 200 de corpo
# vazio continuaria virando "lista vazia". Sem o ParseOk, um 200 com HTML/texto virava Body = $null, o
# extrator de listas lia isso como lista vazia e a checagem da biblioteca saia [OK] sem ter lido nada:
# a escolha do jogo do bloco 4 caia no primeiro do catalogo, SEM verificacao (falha ABERTA medida na
# revisao final). O catch continua engolindo a excecao (o script nao pode morrer no meio de uma
# checagem), mas o resultado NAO e ambiguo: Body = $null COM ParseOk = $false e "corpo ilegivel";
# Body = $null COM ParseOk = $true e "JSON valido que e null" (o literal `null`).
function Partir($raw) {
    $i = $raw.LastIndexOf('|')
    if ($i -lt 0) { return @{ Code = ''; Texto = $raw; Body = $null; ParseOk = $false } }
    $code = $raw.Substring($i + 1).Trim()
    $texto = $raw.Substring(0, $i)
    $obj = $null
    $parseOk = $false
    if (-not [string]::IsNullOrWhiteSpace($texto)) {
        try { $obj = ($texto | ConvertFrom-Json); $parseOk = $true } catch { $obj = $null; $parseOk = $false }
    }
    return @{ Code = $code; Texto = $texto; Body = $obj; ParseOk = $parseOk }
}
function Resposta($url, $method, $bodyArg, $token) {
    $a = @('-s', '--max-time', '60', '-X', $method)
    if ($bodyArg) { $a += @('-H', 'Content-Type: application/json', '-d', $bodyArg) }
    if ($token) { $a += @('-H', ('Authorization: Bearer ' + $token)) }
    $a += @('-w', '|%{http_code}', $url)
    return (Partir (San ([string](& curl.exe @a))))
}
function Status($url, $method, $bodyArg, $token) {
    $r = Resposta $url $method $bodyArg $token
    return $r.Code
}
# Segredo do cluster decodificado em memoria (nunca um valor escrito no script).
function SecretValor($nome, $chave) {
    $s = $null
    try { $s = (kubectl get -n $namespace secret $nome -o json 2>&1 | Out-String | ConvertFrom-Json) } catch { return $null }
    if (-not $s -or -not $s.data) { return $null }
    # Acesso por PSObject: o nome da chave tem hifen ("sa-password") e nao pode virar token.
    $prop = $s.data.PSObject.Properties[$chave]
    if (-not $prop) { return $null }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$prop.Value))
}
# Roda um SQL DENTRO do pod do SQL Server pela unica receita sem aspas internas: o texto vai por
# STDIN para /tmp dentro do pod, o sqlcmd le com -i (e -h -1 quando so o valor interessa) e o arquivo
# e removido no fim. A senha e o $SA_PASSWORD que o pod ja tem no ambiente -- nunca em argv.
#
# POR QUE ASSIM (defeito medido, duas vezes): a forma antiga, com a query entre aspas dentro do
# argumento do shell e -Q, NAO funciona no Windows -- o PowerShell 5.1 entrega aquele argumento
# PICADO em varios pedacos ao processo filho, o shell do container executa so o primeiro e o SQL vai
# TRUNCADO ("... -C -Q UPDATE"), com o sqlcmd respondendo "Msg 102 ... Incorrect syntax near".
# Nenhuma aspas interna aqui: o unico argumento do shell e o caminho do arquivo.
function SqlNoPod($sql, [switch]$SomenteValor) {
    $argsSqlcmd = '-C -i /tmp/fcg-preflight.sql'
    if ($SomenteValor) { $argsSqlcmd = '-C -h -1 -i /tmp/fcg-preflight.sql' }
    $sql | kubectl exec -i -n $namespace deploy/sqlserver -- sh -c 'cat > /tmp/fcg-preflight.sql' 2>&1 | Out-Null
    $saida = (San (((kubectl exec -n $namespace deploy/sqlserver -- sh -c ('/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $SA_PASSWORD ' + $argsSqlcmd) 2>&1) | ForEach-Object { [string]$_ }) -join "`n")).Trim()
    kubectl exec -n $namespace deploy/sqlserver -- sh -c 'rm -f /tmp/fcg-preflight.sql' 2>&1 | Out-Null
    return $saida
}
# Promove o usuario de demonstracao a Admin (o POST /api/jogos exige Admin) e CONFERE o efeito pelo
# mesmo caminho: sem isso, um SQL truncado deixaria o UPDATE sem efeito e o login continuaria
# respondendo 200 (ele funciona com qualquer role) -- a falha so apareceria adiante, no POST de jogo.
# Devolve @{ Saida = ...; Role = ... } para o chamador imprimir e checar.
function PromoverDemoAdmin($email) {
    $saida = SqlNoPod ("UPDATE FCG_Users.dbo.Users SET Role = 1 WHERE Email = '" + $email + "'")
    $role = SqlNoPod ("SELECT Role FROM FCG_Users.dbo.Users WHERE Email = '" + $email + "'") -SomenteValor
    return @{ Saida = $saida; Role = $role }
}
function Pods($seletor) {
    return @(kubectl get -n $namespace pods -l $seletor --no-headers 2>&1 | Where-Object { $_ -match '\S' -and $_ -notmatch 'No resources found' })
}
function Prontos($seletor) {
    return @(kubectl get -n $namespace pods -l $seletor --no-headers 2>&1 | Where-Object { $_ -match '\s1/1\s+Running' }).Count
}
function Kraw($caminho) {
    return (San (((kubectl get --raw $caminho 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
}
# O /metrics de uma API alcancado pelo proxy do kubectl (mesma ideia do Prometheus e do Loki:
# nenhum port-forward no preflight).
function Metricas($servico) {
    return (San (((kubectl get --raw ('/api/v1/namespaces/' + $namespace + '/services/' + $servico + '/proxy/metrics') 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
}
# Le um claim do JWT sem dependencia externa (o payload e base64url). O userId do corpo da compra
# e o claim Id do token -- o endpoint ignora um "usuarioId" vindo do corpo.
function Claim($token, $nome) {
    if (-not $token) { return $null }
    $p = ($token -split '\.')[1]
    $p = $p.Replace('-', '+').Replace('_', '/')
    switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
    try { return (([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json).$nome) } catch { return $null }
}
# Itens da biblioteca, ja sem o envelope: a resposta medida e uma LISTA DIRETA, mas o extrator aceita
# tambem { "itens": [...] } / { "jogos": [...] } / { "biblioteca": [...] } / { "items": [...] }.
# Usado para distinguir "lista vazia" (legitimo) de "tem itens e nenhum id reconhecido" (contrato).
function ItensDaBiblioteca($corpo) {
    if (-not $corpo) { return @() }
    $lista = $corpo
    foreach ($prop in @('itens', 'jogos', 'biblioteca', 'items')) {
        $p = $corpo.PSObject.Properties[$prop]
        if ($p -and $p.Value) { $lista = $p.Value; break }
    }
    return @($lista | Where-Object { $_ -ne $null })
}
# Ids dos jogos que o usuario tem na biblioteca. A resposta medida no cluster e uma LISTA DIRETA de
# itens com o id no campo "gameId":
#   [{"gameId":"7ed3f967-...","nome":"Elden Ring","descricao":"...","preco":199.90,"dataCompra":"..."}, ...]
# (o defeito da rodada 2 foi justamente este: o extrator procurava "id"/"jogoId" e devolvia ZERO ids,
# entao a biblioteca parecia vazia e o jogo do bloco 4 era escolhido no escuro.)
# O extrator aceita: "gameId", "id", "jogoId", "game_id" e os aninhados "jogo.id"/"game.id", em
# QUALQUER caixa (a comparacao de NOME e feita com ToLower, sem depender do indexador do PSObject), e
# tambem uma lista de ids puros (["guid", "guid"]). Quando nada e reconhecido numa resposta com itens,
# preenche $script:camposBiblioteca com os nomes de campo encontrados -- o chamador imprime isso e
# REPROVA (nao basta o transporte ter respondido 200).
function IdsDaBiblioteca($corpo) {
    $script:camposBiblioteca = ''
    if (-not $corpo) { return @() }
    $itens = @(ItensDaBiblioteca $corpo)
    $ids = @()
    foreach ($item in $itens) {
        if ($item -is [string]) { $ids += $item; continue }
        $props = @($item.PSObject.Properties)
        $id = $null
        foreach ($chave in @('gameid', 'id', 'jogoid', 'game_id', 'jogo_id')) {
            $pr = @($props | Where-Object { $_.Name.ToLower() -eq $chave } | Select-Object -First 1)
            if ($pr.Count -gt 0 -and $pr[0].Value) { $id = $pr[0].Value; break }
        }
        if (-not $id) {
            foreach ($aninhado in @('jogo', 'game')) {
                $pr = @($props | Where-Object { $_.Name.ToLower() -eq $aninhado } | Select-Object -First 1)
                if ($pr.Count -gt 0 -and $pr[0].Value) {
                    $sub = @($pr[0].Value.PSObject.Properties | Where-Object { $_.Name.ToLower() -eq 'id' } | Select-Object -First 1)
                    if ($sub.Count -gt 0 -and $sub[0].Value) { $id = $sub[0].Value; break }
                }
            }
        }
        if ($id) { $ids += [string]$id }
    }
    # Diagnostico: itens existem, mas nenhum id reconhecido -> mostra os campos do primeiro item.
    if (($ids.Count -eq 0) -and ($itens.Count -gt 0) -and ($itens[0] -isnot [string])) {
        $script:camposBiblioteca = (@($itens[0].PSObject.Properties | ForEach-Object { $_.Name }) -join ', ')
    }
    return $ids
}
# A API do Grafana e alcancada de DENTRO do pod (wget do proprio container): nao ha port-forward.
# A SENHA NAO VAI NO argv DO kubectl exec (achado I3 da revisao final): ela ja esta no ambiente do
# container (GF_SECURITY_ADMIN_PASSWORD, do Secret grafana-admin), entao quem a expande e o shell de
# dentro do pod -- antes ia embutida na URL como argumento, visivel na linha de comando do kubectl no
# host e no ps do pod. Um unico argumento para o sh -c e SEM aspas internas, pela mesma armadilha do
# PowerShell 5.1 que picava o argumento do sqlcmd.
# Defensivo: se a senha tiver um caractere que quebra o userinfo da URL ("#", "?", "/"), o wget nao
# autentica e o Grafana responde 401 "Invalid username or password" -- nesse caso a chamada e repetida
# com --user/--password (que nao passam por URL). Se a imagem nao suportar essas flags, a resposta
# original volta e as checagens reprovam com a causa a vista.
function GrafanaApi($caminho) {
    $cmdGrafana = 'wget -qO- http://admin:$GF_SECURITY_ADMIN_PASSWORD@localhost:3000' + $caminho
    $respostaGrafana = (San (((kubectl exec -n $namespace deploy/grafana -- sh -c $cmdGrafana 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
    if ($respostaGrafana -match 'Invalid username or password') {
        $cmdGrafanaSenha = 'wget -qO- --user=admin --password=$GF_SECURITY_ADMIN_PASSWORD http://localhost:3000' + $caminho
        $respostaSemUrl = (San (((kubectl exec -n $namespace deploy/grafana -- sh -c $cmdGrafanaSenha 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
        if ($respostaSemUrl -match '\S') { return $respostaSemUrl }
    }
    return $respostaGrafana
}
function Token {
    $b = Body 'login.json' ('{"email":"' + $Email + '","senha":"' + $Senha + '"}')
    $r = Resposta ($Gateway + '/api/auth/login') 'POST' $b $null
    # Guarda o status para a evidencia: o corpo do login traz o token e nunca e impresso.
    $script:ultimoLogin = $r.Code
    if ($r.Body) { return $r.Body.token }
    return $null
}

# A senha so e exigida por quem faz login: o preflight completo e os modulos 2 a 5. Os modulos 1
# (README + pods) e 6 (repositorios + evidencia de segredos) nao tocam em dado nenhum do cluster.
$precisaSenha = (($Modulo -eq 0) -or (@(2, 3, 4, 5) -contains $Modulo))
if ($precisaSenha -and (-not $Senha)) {
    Write-Output 'FALHOU: a senha da demonstracao nao foi informada.'
    Write-Output 'Defina a variavel de ambiente e rode de novo (a senha NUNCA e versionada):'
    Write-Output '  $env:FCG_DEMO_SENHA = ''<senha-da-demonstracao>'''
    Write-Output '  powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1'
    Write-Output 'A senha precisa atender a politica do cadastro: 8+ caracteres, com ao menos uma letra,'
    Write-Output 'um digito e um caractere especial.'
    if ($Modulo -gt 0) {
        Write-Output ('  (o modulo ' + $Modulo + ' faz login com o usuario de demonstracao e por isso exige a senha)')
    }
    exit 1
}
$script:segredos += $Senha
# O diretorio temporario so nasce depois da checagem da senha (nada e criado se ela faltar).
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# ============================================================================================
# MODO POR MODULO (-Modulo N): prepara UMA tomada da gravacao modular e TERMINA o script aqui.
# Sem o parametro (-Modulo 0) NADA deste bloco roda: o preflight completo abaixo segue identico.
# O que cada modulo valida e prepara:
#   1  os 11 pods da plataforma + promtail Running e o README com a secao Arquitetura. Nao consome nada.
#   2  os pods + gateway (401 sem token, login 200, 200 com token) + usuario demo EXISTENTE (cria se
#      faltar) + porta 8001 livre no host (o port-forward da Admin API e desta tomada) + a config do
#      Kong SEM rota para o payments-api e COM o plugin jwt (lida do Secret; so o resumo e impresso).
#   3  os pods + as 3 filas notifications-* + ScaledObject Ready=True + Loki ready com log da funcao na
#      janela de 24h + Grafana com o datasource/dashboard de logs + porta 13000 livre + a funcao em
#      0 replicas (espera ate 120s o cooldown do KEDA). NAO faz cadastro: o cadastro e da tomada.
#   4  as portas 13000/19090 livres + os 3 alvos up no Prometheus + o dashboard FCG - APIs + um JOGO
#      LIVRE garantido e impresso para a compra (cria um se o demo possuir todos -- e o que protege o
#      RETAKE) + o contador fcg_payments_processados_total no /metrics (com uma compra de verificacao em
#      OUTRO jogo livre, so quando o cluster esta frio).
#   5  o jogo da tomada (FCG_DEMO_JOGO, ou reelegido e impresso) + o PUT/GET de avaliacoes (upsert) +
#      as chaves catalog:* no Redis + os contadores cache_hit/cache_miss.
#   6  os 5 repositorios locais sem alteracao pendente + a evidencia de segredos devolvendo vazio + o
#      link do repositorio da funcao e a secao de requisitos no README.
# ============================================================================================
if ($Modulo -gt 0) {

    # A porta esta livre se da para BINDAR nela agora: e a porta que o port-forward da tomada vai usar.
    function PortaLivre($porta) {
        $ouvinte = $null
        try {
            $ouvinte = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $porta)
            $ouvinte.Start()
            $ouvinte.Stop()
            return $true
        } catch {
            if ($ouvinte) { try { $ouvinte.Stop() } catch { } }
            return $false
        }
    }

    # Os 11 pods da plataforma + o promtail (DaemonSet, quem coleta o log): e o que a abertura mostra.
    function ChecarPodsDaPlataforma() {
        'pods do namespace:'
        kubectl get -n $namespace pods --no-headers 2>&1 | ForEach-Object { '  ' + $_ }
        foreach ($app in @('sqlserver', 'rabbitmq', 'mongo', 'redis', 'users-api', 'catalog-api', 'payments-api', 'kong', 'prometheus', 'grafana', 'loki')) {
            Chk ((Prontos ('app=' + $app)) -ge 1) ('pod-' + $app + '-1/1-Running')
        }
        Chk ((Prontos 'app=promtail') -ge 1) 'pod-promtail-1/1-Running'
    }

    # CONTRATO DAS FUNCOES DESTE MODO: elas IMPRIMEM as linhas na tela e por isso NAO devolvem valor --
    # o resultado sai nas variaveis de escopo de script abaixo. Devolver o token (ou o jogo) junto com
    # as linhas impressas faria o PowerShell juntar tudo num array e o valor viraria lixo.
    $script:tomadaToken = $null
    $script:tomadaJogoId = ''
    $script:tomadaJogoNome = ''
    $script:tomadaJogos = @()
    $script:tomadaBiblioteca = @()
    $script:grafanaDatasources = @()
    $script:grafanaDashboards = @()

    # O usuario de demonstracao PRECISA existir (as tomadas 2, 4 e 5 fazem login com ele): se o login
    # falhar, o preparo CRIA o usuario pelo gateway, como o preflight completo faz no P3.
    function GarantirUsuarioDemo() {
        $t = Token
        'POST /api/auth/login = ' + $script:ultimoLogin + '  (esperado 200)'
        if (-not $t) {
            'login falhou: criando o usuario de demonstracao pelo gateway (POST /api/usuarios)...'
            $bCad = Body 'cadastro-demo.json' ('{"nome":"' + $Nome + '","email":"' + $Email + '","senha":"' + $Senha + '"}')
            $rCad = Resposta ($Gateway + '/api/usuarios') 'POST' $bCad $null
            'POST /api/usuarios = ' + $rCad.Code + '  (esperado 201)'
            if ($rCad.Code -eq '400') {
                'ATENCAO: o cadastro respondeu 400 -- o e-mail ja existe com OUTRA senha (o login falhou)'
                'ATENCAO: ou a senha nao atende a politica (8+ caracteres, com letra, digito e caractere especial).'
            }
            $t = Token
            if ($t) {
                Write-Output '*** AVISO: o usuario de demonstracao NAO existia e foi CRIADO agora pelo preflight. ***'
                Write-Output '*** AVISO: a criacao publica UserCreatedEvent e ACORDA a funcao serverless: se a proxima ***'
                Write-Output '*** AVISO: tomada for a do modulo 3, o preparo dela espera o cooldown antes de liberar. ***'
            }
        }
        Chk ([bool]$t) 'usuario-de-demonstracao-login-200'
        if ($t) { 'token obtido: ' + $t.Length + ' caracteres (valor nunca e impresso)' }
        $script:tomadaToken = $t
    }

    # O JOGO DA TOMADA: o primeiro do catalogo que o usuario demo NAO possui (o catalogo volta ordenado
    # por NOME e a biblioteca cresce a cada rodada). Se ele possuir todos, o preparo CRIA um jogo novo --
    # e por isso rodar o preparo de novo antes de um RETAKE devolve um jogo livre: sem isso a compra da
    # tomada responderia 400 ("ja possui este jogo") e o painel de pagamentos nao se mexeria na tela.
    # A posse e VERIFICADA (existe no catalogo E nao esta na biblioteca lida) e o id fica impresso para
    # o apresentador copiar para $env:FCG_DEMO_JOGO antes de apertar REC.
    function GarantirJogoLivre() {
        $script:tomadaJogoId = ''
        $script:tomadaJogoNome = ''
        $script:tomadaJogos = @()
        $script:tomadaBiblioteca = @()
        if (-not $script:tomadaToken) { return }
        $userId = Claim $script:tomadaToken 'Id'
        'userId (claim Id do token) = ' + $userId
        $lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $script:tomadaToken
        $jogos = @($lista.Body | Where-Object { $_ -ne $null })
        'GET /api/jogos = ' + $lista.Code + '  jogos no catalogo = ' + $jogos.Count
        Chk ($lista.Code -eq '200' -and $lista.ParseOk) 'catalogo-listagem-200'
        if (-not $lista.ParseOk) {
            Write-Output ('FALHOU: GET /api/jogos respondeu ' + $lista.Code + ' com um corpo que NAO deu para ler como')
            Write-Output 'FALHOU: JSON: nao ha catalogo para escolher o jogo da tomada, e NADA sera criado a partir dele.'
            return
        }
        $idsBiblioteca = @()
        $bibliotecaLida = $false
        if ($userId) {
            $bib = Resposta ($Gateway + '/api/biblioteca/' + $userId) 'GET' $null $script:tomadaToken
            'GET /api/biblioteca/{userId} = ' + $bib.Code + '  (a biblioteca do usuario demo)'
            if ($bib.Code -eq '200') {
                $itens = @(ItensDaBiblioteca $bib.Body)
                $idsBiblioteca = @(IdsDaBiblioteca $bib.Body | ForEach-Object { ([string]$_).ToLower() })
                $interpretavel = ($bib.ParseOk -and (($itens.Count -eq 0) -or ($idsBiblioteca.Count -eq $itens.Count)))
                'biblioteca do usuario demo = ' + $itens.Count + ' item(ns), ' + $idsBiblioteca.Count + ' id(s) reconhecido(s)'
                Chk $interpretavel 'biblioteca-do-usuario-200'
                if ($interpretavel) {
                    $bibliotecaLida = $true
                } else {
                    Write-Output 'FALHOU: a biblioteca respondeu 200 com um corpo que nao deu para interpretar (contrato):'
                    Write-Output 'FALHOU: sem os ids a posse NAO pode ser verificada e a compra do video poderia dar 400.'
                }
            } elseif ($bib.Code -eq '404') {
                Write-Output 'ATENCAO: GET /api/biblioteca/{userId} respondeu 404: o usuario demo ainda nao tem'
                Write-Output 'ATENCAO: biblioteca (nada possuido), entao qualquer jogo do catalogo esta livre.'
                Write-Output '(esta situacao NAO entra na contagem de checagens: e estado legitimo, nao falha)'
            } else {
                Write-Output ('FALHOU: GET /api/biblioteca/{userId} devolveu ' + $bib.Code + ' -- sem a biblioteca a posse do')
                Write-Output 'FALHOU: jogo da tomada NAO pode ser verificada (a compra do video poderia responder 400).'
                Chk $false 'biblioteca-do-usuario-200'
            }
        }
        $jogo = $null
        $nome = ''
        $tentativa = 0
        while ((-not $jogo) -and ($tentativa -lt 3)) {
            $tentativa++
            for ($i = 0; $i -lt $jogos.Count; $i++) {
                $idCand = [string]$jogos[$i].id
                if ($idCand -and ($idsBiblioteca -notcontains $idCand.ToLower())) { $jogo = $idCand; $nome = [string]$jogos[$i].nome; break }
            }
            if (-not $jogo) {
                # Todos os jogos do catalogo ja sao dele: cria mais um (o POST de jogo exige Admin).
                'todos os jogos do catalogo ja estao na biblioteca do usuario demo: criando mais um'
                $nomeExtra = 'Jogo Demo Livre Tomada ' + $tentativa
                $bExtra = Body ('jogo-extra-tomada-' + $tentativa + '.json') ('{"nome":"' + $nomeExtra + '","descricao":"Jogo livre para a compra do video","preco":89.90}')
                $rExtra = Resposta ($Gateway + '/api/jogos') 'POST' $bExtra $script:tomadaToken
                'POST /api/jogos = ' + $rExtra.Code + '  (esperado 201)  nome=' + $nomeExtra
                if ($rExtra.Code -ne '201') {
                    $saExtra = SecretValor 'sqlserver-secret' 'sa-password'
                    if ($saExtra) {
                        $script:segredos += $saExtra
                        'POST recusado (' + $rExtra.Code + '): promovendo o usuario demo a Admin e tentando de novo'
                        $promoExtra = PromoverDemoAdmin $Email
                        'Role lido do SQL depois do UPDATE = [' + ($promoExtra.Role -replace "`r?`n", ' ') + ']  (esperado 1)'
                        $tNovo = Token
                        if ($tNovo) { $script:tomadaToken = $tNovo }
                        $rExtra = Resposta ($Gateway + '/api/jogos') 'POST' $bExtra $script:tomadaToken
                        'POST /api/jogos (apos a promocao) = ' + $rExtra.Code + '  (esperado 201)'
                    } else {
                        'NAO consegui ler o Secret sqlserver-secret/sa-password: nao ha como promover o usuario'
                    }
                    if ($rExtra.Code -ne '201') { break }
                }
                $lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $script:tomadaToken
                $jogos = @($lista.Body | Where-Object { $_ -ne $null })
            }
        }
        $idsCatalogo = @($jogos | ForEach-Object { ([string]$_.id).ToLower() })
        $idEscolhido = ''
        if ($jogo) { $idEscolhido = ([string]$jogo).ToLower() }
        $existeNoCatalogo = [bool]($idEscolhido -and ($idsCatalogo -contains $idEscolhido))
        if ($bibliotecaLida) {
            $estaNaBiblioteca = ($idsBiblioteca -contains $idEscolhido)
            $livre = [bool]($existeNoCatalogo -and (-not $estaNaBiblioteca))
            if ($estaNaBiblioteca) {
                Write-Output ('FALHOU: o jogo escolhido para a tomada (' + $jogo + ') ESTA na biblioteca do usuario demo:')
                Write-Output 'FALHOU: a compra do video responderia 400 e o painel de pagamentos nao se mexeria.'
            }
            if (-not $existeNoCatalogo) {
                Write-Output ('FALHOU: o jogo escolhido (' + $jogo + ') nao esta na lista do catalogo lida.')
            }
            'jogo da tomada livre = ' + $livre + '  (existe no catalogo=' + $existeNoCatalogo + '  esta na biblioteca=' + $estaNaBiblioteca + ')'
            Chk $livre 'jogo-do-bloco-4-escolhido'
        } else {
            if ($existeNoCatalogo) {
                Write-Output 'ATENCAO: sem a biblioteca lida nao da para garantir que o jogo escolhido esta livre'
                Write-Output ('ATENCAO: (ele existe no catalogo=' + $existeNoCatalogo + ', mas a posse nao foi verificada).')
                Write-Output '(esta situacao NAO entra na contagem de checagens: a posse nao pode ser verificada)'
            } else {
                Write-Output 'FALHOU: nenhum jogo valido foi escolhido para a tomada -- sem jogo, a compra do modulo 4'
                Write-Output 'FALHOU: ficaria sem o que comprar e o painel de pagamentos sem evidencia.'
                Chk $false 'jogo-do-bloco-4-escolhido'
            }
        }
        $script:tomadaJogos = $jogos
        $script:tomadaBiblioteca = $idsBiblioteca
        if ($jogo) {
            $script:tomadaJogoId = [string]$jogo
            $script:tomadaJogoNome = [string]$nome
        }
    }

    # As 3 filas do broker e o ScaledObject Ready (sem fila o KEDA cai em TriggerError e a funcao
    # simplesmente NAO SOBE -- falha silenciosa que so apareceria na gravacao).
    function ChecarKedaEFilas() {
        $filas = (San (((kubectl exec -n $namespace deploy/rabbitmq -- rabbitmqctl list_queues name 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
        'filas do broker (rabbitmqctl list_queues name):'
        $filas -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { '  ' + $_.Trim() }
        foreach ($fila in @('notifications-user-created', 'notifications-payment-processed', 'notifications-dead-letter')) {
            Chk ($filas -match [regex]::Escape($fila)) ('fila-' + $fila)
        }
        $so = $null
        try { $so = (kubectl get -n $namespace scaledobject notifications-function -o json 2>&1 | Out-String | ConvertFrom-Json) } catch { $so = $null }
        if ($so) {
            $readySo = ($so.status.conditions | Where-Object { $_.type -eq 'Ready' }).status
            'ScaledObject notifications-function Ready=' + $readySo + '  min=' + $so.spec.minReplicaCount + ' max=' + $so.spec.maxReplicaCount
            Chk ($readySo -eq 'True') 'scaledobject-Ready-True'
            if ($readySo -ne 'True') {
                'TriggerError costuma ser fila ausente no broker: rode o terraform apply do repositorio da funcao.'
            }
        } else {
            'ScaledObject notifications-function nao encontrado: a funcao nao esta implantada (terraform apply do repo dela)'
            Chk $false 'scaledobject-Ready-True'
        }
    }

    # Loki pronto e com log: o painel que a tomada do modulo 3 mostra e o do Loki, e o log DA FUNCAO e o
    # que prova que ela rodou. O rotulo da funcao so nasce depois de ela subir uma vez na retencao de
    # 24h: quando ele ainda nao existe a situacao e ATENCAO (sem contar checagem), porque o cadastro da
    # propria tomada gera a linha ao vivo -- reprovar por isso bloquearia uma gravacao valida.
    function ChecarLokiELogDaFuncao() {
        $ready = (Kraw ('/api/v1/namespaces/' + $namespace + '/services/loki:3100/proxy/ready')).Trim()
        'loki /ready = ' + $ready + '  (esperado ready)'
        Chk ($ready -eq 'ready') 'loki-ready'
        $rotulos = @()
        for ($i = 0; $i -lt 4; $i++) {
            try {
                $resp = (Kraw ('/api/v1/namespaces/' + $namespace + '/services/loki:3100/proxy/loki/api/v1/label/app/values'))
                $lido = ($resp | ConvertFrom-Json).data
                # @($null) conta como UM elemento no PowerShell: o filtro evita aprovar sem ter lido nada.
                $rotulos = @($lido | Where-Object { $_ -ne $null })
            } catch { $rotulos = @() }
            if ($rotulos.Count -gt 0) { break }
            Start-Sleep -Seconds 5
        }
        'rotulos app no Loki = ' + $(if ($rotulos.Count -gt 0) { $rotulos -join ', ' } else { '(nenhum)' })
        Chk ($rotulos.Count -ge 1) 'loki-rotulo-app-com-log'
        $temLogDaFuncao = ($rotulos -contains 'notifications-function')
        if ($temLogDaFuncao) {
            # O filtro vai URL-encoded ({app="notifications-function"} tem chaves e aspas, que o
            # PowerShell 5.1 nao entrega inteiras em argumento de processo nativo).
            $agoraLoki = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $caminhoLinhas = ('/api/v1/namespaces/' + $namespace + '/services/loki:3100/proxy/loki/api/v1/query_range?query=%7Bapp%3D%22notifications-function%22%7D&limit=20&start=' + ($agoraLoki - 86400) + '&end=' + $agoraLoki)
            $linhasFuncao = 0
            $respostaLinhas = ''
            try {
                $respostaLinhas = Kraw $caminhoLinhas
                $jsonLinhas = ($respostaLinhas | ConvertFrom-Json)
                foreach ($fluxo in @($jsonLinhas.data.result | Where-Object { $_ -ne $null })) {
                    if ($fluxo.values) { $linhasFuncao += @($fluxo.values | Where-Object { $_ -ne $null }).Count }
                }
            } catch { $linhasFuncao = 0 }
            'linhas de notifications-function na janela de 24h = ' + $linhasFuncao + '  (esperado >= 1)'
            if ($linhasFuncao -lt 1) {
                Write-Output 'FALHOU: o rotulo notifications-function existe no Loki, mas nenhuma LINHA foi lida na'
                Write-Output 'FALHOU: janela de 24h -- o painel de logs da tomada nao teria o que mostrar. Remedio: um'
                Write-Output 'FALHOU: cadastro pelo gateway gera uma linha nova; se ainda assim nao aparecer, confira'
                Write-Output 'FALHOU: o Promtail (k8s/promtail-deployment.yaml), que e quem coleta o log dos pods.'
                $amostraLinhas = (San ((([string]$respostaLinhas) -replace '\s+', ' '))).Trim()
                if ($amostraLinhas.Length -gt 300) { $amostraLinhas = $amostraLinhas.Substring(0, 300) }
                Write-Output ('  resposta do Loki (resumida) = ' + $(if ($amostraLinhas) { $amostraLinhas } else { '(vazia)' }))
            }
            Chk ($linhasFuncao -ge 1) 'loki-log-da-funcao-de-notificacoes'
        } else {
            Write-Output 'ATENCAO: ainda nao ha log de notifications-function no Loki (a funcao nao rodou nas ultimas'
            Write-Output 'ATENCAO: 24h). A tomada continua valida: o cadastro dela acorda a funcao e a linha aparece'
            Write-Output 'ATENCAO: ao vivo no painel -- e essa linha viva que o modulo 3 mostra.'
            Write-Output '(esta situacao NAO entra na contagem de checagens: nao ha o que verificar ainda)'
        }
    }

    # Saude, datasources e dashboards do Grafana (a senha e lida do Secret em memoria e nunca e impressa).
    function GrafanaAberto() {
        $script:senhaGrafana = SecretValor 'grafana-admin' 'admin-password'
        if ($script:senhaGrafana) {
            $script:segredos += $script:senhaGrafana
            $script:segredos += [uri]::EscapeDataString($script:senhaGrafana)
        }
        $health = $null
        try { $health = (GrafanaApi '/api/health' | ConvertFrom-Json) } catch { $health = $null }
        'grafana /api/health = ' + $(if ($health) { 'database=' + $health.database + ' version=' + $health.version } else { '(sem resposta)' })
        Chk ($health -and $health.database -eq 'ok') 'grafana-health-ok'
        $ds = @()
        try { $ds = @(GrafanaApi '/api/datasources' | ConvertFrom-Json) } catch { $ds = @() }
        $uidsDs = @($ds | ForEach-Object { $_.uid })
        'datasources = ' + $(if ($uidsDs.Count -gt 0) { $uidsDs -join ', ' } else { '(nenhum)' })
        $dash = @()
        try { $dash = @(GrafanaApi '/api/search?query=FCG' | ConvertFrom-Json) } catch { $dash = @() }
        $uidsDash = @($dash | ForEach-Object { $_.uid })
        'dashboards encontrados = ' + $(if ($uidsDash.Count -gt 0) { $uidsDash -join ', ' } else { '(nenhum)' })
        $script:grafanaDatasources = $uidsDs
        $script:grafanaDashboards = $uidsDash
    }

    # Os alvos do job fcg-apis no Prometheus, pelo proxy do kubectl (sem port-forward).
    function ChecarAlvosDoPrometheus() {
        $alvos = $null
        try { $alvos = ((kubectl get --raw ('/api/v1/namespaces/' + $namespace + '/services/prometheus:9090/proxy/api/v1/targets') 2>&1) | Out-String | ConvertFrom-Json) } catch { $alvos = $null }
        if ($alvos) {
            # O Where-Object nao e enfeite: sem ele, um campo ausente vira @($null), que o PowerShell
            # conta como UM elemento e faria a checagem passar sem ter lido alvo nenhum.
            $ativos = @($alvos.data.activeTargets | Where-Object { $_ -ne $null })
            foreach ($t in $ativos) { '  alvo job=' + $t.labels.job + ' ' + $t.scrapeUrl + ' health=' + $t.health }
            $fcg = @($ativos | Where-Object { $_.labels.job -eq 'fcg-apis' })
            Chk ($fcg.Count -eq 3) 'prometheus-tres-alvos-fcg-apis'
            foreach ($api in @('users-api', 'catalog-api', 'payments-api')) {
                Chk ([bool](@($fcg | Where-Object { $_.scrapeUrl -match ($api + ':80') -and $_.health -eq 'up' }))) ('prometheus-alvo-' + $api + '-up')
            }
            Chk ((@($ativos | Where-Object { $_.health -ne 'up' }).Count) -eq 0) 'prometheus-nenhum-alvo-down'
        } else {
            'PROMETHEUS INACESSIVEL pelo proxy do kubectl (get --raw .../services/prometheus:9090/proxy/api/v1/targets)'
            Chk $false 'prometheus-tres-alvos-fcg-apis'
        }
    }

    $token = $null
    try {
        if ($Modulo -eq 1) {
            Step 'MODULO 1 - abertura e arquitetura: a plataforma no ar e o README na mao'
            # Nao consome nada: so le o cluster e o disco.
            ChecarPodsDaPlataforma
            $raizRepo = Split-Path -Parent $PSScriptRoot
            $caminhoReadme = Join-Path $raizRepo 'README.md'
            'README da plataforma = ' + $caminhoReadme
            $temArquitetura = $false
            $temFluxo = $false
            if (Test-Path $caminhoReadme) {
                $temArquitetura = [bool](Select-String -Path $caminhoReadme -Pattern '^## Arquitetura' -Quiet)
                $temFluxo = [bool](Select-String -Path $caminhoReadme -Pattern '^### Fluxo de eventos' -Quiet)
            } else {
                Write-Output 'FALHOU: o README.md do repositorio nao existe: e ele que a abertura mostra (secao Arquitetura).'
            }
            'README com a secao Arquitetura = ' + $temArquitetura + '  com o fluxo de eventos = ' + $temFluxo
            Chk ($temArquitetura -and $temFluxo) 'readme-com-arquitetura-e-fluxo-de-eventos'
        } elseif ($Modulo -eq 2) {
            Step 'MODULO 2 - gateway: roteamento e seguranca'
            ChecarPodsDaPlataforma
            $s401 = Status ($Gateway + '/api/jogos') 'GET' $null $null
            'GET /api/jogos sem token = ' + $s401 + '  (esperado 401)'
            Chk ($s401 -eq '401') 'gateway-401-sem-token'
            GarantirUsuarioDemo
            $token = $script:tomadaToken
            $s200 = Status ($Gateway + '/api/jogos') 'GET' $null $token
            'GET /api/jogos com token = ' + $s200 + '  (esperado 200)'
            Chk ($s200 -eq '200') 'gateway-200-com-token'
            $p8001 = PortaLivre 8001
            'porta 8001 no host = ' + $(if ($p8001) { 'livre' } else { 'OCUPADA' }) + '  (o port-forward da Admin API e desta tomada)'
            Chk $p8001 'porta-8001-livre-no-host'
            if (-not $p8001) {
                Write-Output 'a porta 8001 ja esta em uso: feche o port-forward que esta nela (Ctrl+C na janela dele) e'
                Write-Output 'rode o preparo do modulo 2 de novo -- o port-forward da Admin API e DESTA tomada.'
            }
            # A Admin API escuta SO no loopback do pod e nao e publicada no Service: sem port-forward, o
            # unico jeito de provar o roteamento declarado e ler a config DB-less do Secret (em memoria).
            # So o resumo -- nomes de servico e de rota, e a presenca do plugin -- e impresso; o segredo
            # HMAC do consumer vai para a lista do San() e NUNCA aparece na saida.
            $configKong = SecretValor 'kong-declarative-config' 'kong.yml'
            if ($configKong) {
                $segredosKong = [regex]::Matches($configKong, '(?m)^\s*secret:\s*"?([^"\r\n]+)"?\s*$')
                foreach ($m in $segredosKong) { $script:segredos += $m.Groups[1].Value.Trim() }
                $servicosKong = @([regex]::Matches($configKong, '(?m)^  - name: (\S+)') | ForEach-Object { $_.Groups[1].Value })
                $rotasKong = @([regex]::Matches($configKong, '(?m)^      - name: (\S+)') | ForEach-Object { $_.Groups[1].Value })
                'config do Kong lida do Secret kong-declarative-config (so o resumo: nenhum segredo e impresso)'
                'servicos no Kong = ' + $(if ($servicosKong.Count -gt 0) { $servicosKong -join ', ' } else { '(nenhum)' })
                'rotas no Kong = ' + $(if ($rotasKong.Count -gt 0) { $rotasKong -join ', ' } else { '(nenhum)' })
                # Roteamento: quem expoe as APIs e o Kong. O payments-api NAO tem rota (ele e consumidor de
                # fila) -- e essa ausencia e a evidencia de arquitetura que a tomada narra.
                Chk (($rotasKong.Count -ge 1) -and ($configKong -notmatch 'payments-api')) 'kong-sem-rota-para-payments-api'
                # Seguranca: as rotas protegidas levam o plugin jwt (sem ele o 401 sem token nao existiria).
                Chk ($configKong -match '(?m)^\s*- name: jwt') 'kong-com-plugin-jwt'
            } else {
                Write-Output 'FALHOU: nao consegui ler o Secret kong-declarative-config/kong.yml (rode o'
                Write-Output 'FALHOU: scripts/deploy-kong.ps1): sem ele nao da para provar o roteamento antes de gravar.'
                Chk $false 'kong-sem-rota-para-payments-api'
                Chk $false 'kong-com-plugin-jwt'
            }
        } elseif ($Modulo -eq 3) {
            Step 'MODULO 3 - funcao serverless: escala a zero, filas e log na plataforma'
            ChecarPodsDaPlataforma
            ChecarKedaEFilas
            ChecarLokiELogDaFuncao
            GrafanaAberto
            Chk (($script:grafanaDatasources) -contains 'loki') 'grafana-datasource-loki'
            Chk (($script:grafanaDashboards) -contains 'fcg-logs') 'grafana-dashboard-fcg-logs'
            $p13000 = PortaLivre 13000
            'porta 13000 no host = ' + $(if ($p13000) { 'livre' } else { 'OCUPADA' }) + '  (o port-forward do Grafana e desta tomada)'
            Chk $p13000 'porta-13000-livre-no-host'
            if (-not $p13000) {
                Write-Output 'a porta 13000 ja esta em uso: feche o port-forward do Grafana da tomada anterior (Ctrl+C)'
                Write-Output 'e rode o preparo do modulo 3 de novo.'
            }
            # POR ULTIMO a espera da escala a zero: e o estado com que a tomada comeca (o 0/0 na tela) e
            # nada depois daqui acorda a funcao. O KEDA tem cooldownPeriod de 30s e o pod ainda precisa
            # terminar; 120s e o limite -- se estourar, espere um pouco mais e rode o preparo de novo.
            $t0 = Get-Date
            $zero = $false
            while (((Get-Date) - $t0).TotalSeconds -lt 120) {
                $podsFn = @(Pods 'app=notifications-function')
                $repFn = ((kubectl get -n $namespace deployment notifications-function -o jsonpath='{.spec.replicas}' 2>&1) | Out-String).Trim()
                if (($podsFn.Count -eq 0) -and ($repFn -eq '0')) { $zero = $true; break }
                '  aguardando o cooldown do KEDA (30s) + o termino do pod... pods=' + $podsFn.Count + ' replicas=' + $repFn
                Start-Sleep -Seconds 10
            }
            $podsFn = @(Pods 'app=notifications-function')
            $repFn = ((kubectl get -n $namespace deployment notifications-function -o jsonpath='{.spec.replicas}' 2>&1) | Out-String).Trim()
            'deployment notifications-function: replicas=' + $repFn + '  pods=' + $podsFn.Count + '  (esperado 0 e 0)'
            'kubectl get -n default pods -l app=notifications-function = ' + $(if ($podsFn.Count -eq 0) { 'No resources found' } else { ($podsFn -join ' | ') })
            Chk $zero 'funcao-em-zero-replicas-estado-inicial'
            if (-not $zero) {
                Write-Output 'a funcao NAO voltou a zero em 120s: espere o cooldown de 30s mais o termino do pod e rode'
                Write-Output 'o preparo do modulo 3 de novo -- a tomada precisa COMECAR com o 0/0 na tela.'
            }
        } elseif ($Modulo -eq 4) {
            Step 'MODULO 4 - observabilidade: trafego, paineis e o pagamento por evento'
            foreach ($porta in @(13000, 19090)) {
                $livre = PortaLivre $porta
                'porta ' + $porta + ' no host = ' + $(if ($livre) { 'livre' } else { 'OCUPADA' }) + '  (o port-forward da tomada precisa dela)'
                Chk $livre ('porta-' + $porta + '-livre-no-host')
            }
            ChecarAlvosDoPrometheus
            GrafanaAberto
            Chk (($script:grafanaDatasources) -contains 'prometheus') 'grafana-datasource-prometheus'
            Chk (($script:grafanaDashboards) -contains 'fcg-apis') 'grafana-dashboard-fcg-apis'
            GarantirUsuarioDemo
            $token = $script:tomadaToken
            GarantirJogoLivre
            $jogoDaTomada = $script:tomadaJogoId
            $jogoDaTomadaNome = $script:tomadaJogoNome
            # O CONTADOR DE PAGAMENTOS: no prometheus-net 8.2.1 a familia com labels so nasce no primeiro
            # WithLabels, ou seja, depois que o consumidor processa o primeiro OrderPlacedEvent. Num
            # cluster frio ele nao existe e o painel "Pagamentos processados por status" ficaria sem serie
            # na tomada: a compra de verificacao aqui -- em OUTRO jogo LIVRE, nunca no da tomada, que
            # precisa da PRIMEIRA compra daquele par para mover o painel -- cria a familia.
            $mPayments = Metricas 'payments-api:80'
            $temContador = [bool]($mPayments -match '(?m)^fcg_payments_processados_total')
            $alternativo = $null
            $compraOk = $false
            if (-not $temContador) {
                for ($i = $script:tomadaJogos.Count - 1; $i -ge 0; $i--) {
                    $idCand = [string]$script:tomadaJogos[$i].id
                    if ($idCand -and ($idCand -ne $jogoDaTomada) -and ($script:tomadaBiblioteca -notcontains $idCand.ToLower())) { $alternativo = $idCand; break }
                }
                if ($alternativo) {
                    $userId = Claim $token 'Id'
                    $bCompra = Body 'compra.json' ('{"userId":"' + $userId + '","gameId":"' + $alternativo + '"}')
                    $rCompra = Resposta ($Gateway + '/api/jogos/' + $alternativo + '/comprar') 'POST' $bCompra $token
                    'compra de verificacao (jogo ' + $alternativo + ', OUTRO que o da tomada) = ' + $rCompra.Code + '  (esperado 202)'
                    $compraOk = ($rCompra.Code -eq '202')
                    if ($compraOk) {
                        for ($k = 1; $k -le 6; $k++) {
                            Start-Sleep -Seconds 5
                            $mPayments = Metricas 'payments-api:80'
                            if ($mPayments -match '(?m)^fcg_payments_processados_total') { $temContador = $true; break }
                        }
                        Chk ($rCompra.Code -eq '202') 'compra-aceita-202'
                    } elseif (@('400', '409') -contains $rCompra.Code) {
                        Write-Output ('ATENCAO: a compra de verificacao devolveu ' + $rCompra.Code + ' (o usuario demo ja possui')
                        Write-Output 'ATENCAO: ESTE jogo). O jogo da tomada NAO e afetado (foi escolhido por estar livre) e o'
                        Write-Output 'ATENCAO: que se perde e a prova do 202 e do contador nesta rodada.'
                        Write-Output '(esta situacao NAO entra na contagem de checagens: e re-execucao, nao falha)'
                    } else {
                        Write-Output ('FALHOU: a compra de verificacao devolveu ' + $rCompra.Code + ' -- isso NAO e re-execucao (400/409):')
                        Write-Output 'FALHOU: o endpoint POST /api/jogos/{id}/comprar nao esta respondendo como esperado'
                        Write-Output 'FALHOU: (401 = token recusado, 403 = sem permissao, 5xx/000 = servico ou gateway fora).'
                        Chk $false 'compra-aceita-202'
                    }
                } else {
                    Write-Output 'ATENCAO: nao ha outro jogo LIVRE no catalogo para a compra de verificacao (o jogo da'
                    Write-Output 'ATENCAO: tomada nao pode ser consumido aqui) e o contador ainda nao esta no /metrics.'
                    Write-Output '(esta situacao NAO entra na contagem de checagens: a compra DA TOMADA cria a familia)'
                }
            }
            'contador fcg_payments_processados_total no /metrics do payments-api = ' + $temContador
            if ($temContador) {
                Chk $temContador 'metrics-payments-api-contador-de-negocio'
            } elseif ($compraOk) {
                Write-Output 'FALHOU: a compra de verificacao foi ACEITA (202) e publicou o OrderPlacedEvent, mas o contador'
                Write-Output 'FALHOU: fcg_payments_processados_total nao apareceu no /metrics do payments-api nem depois'
                Write-Output 'FALHOU: de 30s: o painel "Pagamentos processados por status" ficaria sem serie na tomada.'
                Chk $false 'metrics-payments-api-contador-de-negocio'
            }
            if ($jogoDaTomada) {
                'jogo do modulo 4 (compra) = ' + $jogoDaTomadaNome + ' (' + $jogoDaTomada + ')'
                '  (nenhum outro jogo foi comprado aqui: a primeira compra DESTE par e a que move o painel na tomada)'
            }
        } elseif ($Modulo -eq 5) {
            Step 'MODULO 5 - NoSQL e cache: avaliacoes no Mongo e o Redis como cache de leitura'
            GarantirUsuarioDemo
            $token = $script:tomadaToken
            # O JOGO DA TOMADA: o mesmo id que o modulo 4 comprou ($env:FCG_DEMO_JOGO), se ele existir no
            # catalogo. Depois de gravar o modulo 4 esse jogo JA pertence ao usuario demo -- a avaliacao e
            # upsert por (gameId, userId) e NAO precisa de jogo livre. Se a variavel nao estiver definida
            # (tomada do modulo 5 gravada antes da do 4), o preparo reelege um jogo livre e imprime o id.
            # O catalogo e lido UMA vez em cada caminho (o id pedido se valida aqui; a eleicao le sozinha).
            $pedido = [string]$env:FCG_DEMO_JOGO
            $jogoDaTomada = ''
            $jogoDaTomadaNome = ''
            if ($pedido) {
                $lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
                $jogos = @($lista.Body | Where-Object { $_ -ne $null })
                'GET /api/jogos = ' + $lista.Code + '  jogos no catalogo = ' + $jogos.Count
                Chk ($lista.Code -eq '200' -and $lista.ParseOk) 'catalogo-listagem-200'
                if ($lista.ParseOk) {
                    $achado = @($jogos | Where-Object { ([string]$_.id).ToLower() -eq $pedido.ToLower() })
                    if ($achado.Count -ge 1) {
                        $jogoDaTomada = [string]$achado[0].id
                        $jogoDaTomadaNome = [string]$achado[0].nome
                    }
                }
            }
            if ($jogoDaTomada) {
                'jogo da tomada = ' + $jogoDaTomadaNome + ' (' + $jogoDaTomada + ')  -- veio de FCG_DEMO_JOGO'
            } else {
                if ($pedido) {
                    'FCG_DEMO_JOGO = ' + $pedido + ' nao esta no catalogo: reelegendo um jogo livre e imprimindo o id'
                } else {
                    'FCG_DEMO_JOGO nao esta definido nesta sessao: reelegendo um jogo livre e imprimindo o id'
                }
                GarantirJogoLivre
                $jogoDaTomada = $script:tomadaJogoId
                $jogoDaTomadaNome = $script:tomadaJogoNome
            }
            Chk ([bool]$jogoDaTomada) 'jogo-da-tomada-definido'
            if ($jogoDaTomada) {
                # O PUT e upsert por (gameId, userId): 201 na primeira avaliacao e 200 ao atualizar. Como
                # ESTE preparo ja gravou a avaliacao do demo neste jogo, na gravacao o PUT devolve 200.
                $bAval = Body 'avaliacao.json' '{"nota":5,"comentario":"Jogo muito bom","tags":["acao","video"]}'
                $rAval = Resposta ($Gateway + '/api/jogos/' + $jogoDaTomada + '/avaliacoes') 'PUT' $bAval $token
                'PUT /api/jogos/{id}/avaliacoes = ' + $rAval.Code + '  (esperado 201 na primeira, 200 na atualizacao)'
                Chk (@('200', '201') -contains $rAval.Code) 'avaliacao-upsert-200-ou-201'
                $rListaAval = Resposta ($Gateway + '/api/jogos/' + $jogoDaTomada + '/avaliacoes') 'GET' $null $token
                'GET /api/jogos/{id}/avaliacoes = ' + $rListaAval.Code + '  (esperado 200: a lista vem do Mongo)'
                Chk ($rListaAval.Code -eq '200') 'avaliacao-listagem-200'
            } else {
                'sem jogo da tomada: a avaliacao do modulo 5 nao pode ser exercitada'
                Chk $false 'avaliacao-upsert-200-ou-201'
                Chk $false 'avaliacao-listagem-200'
            }
            # O TTL da chave e de 60s: a listagem e lida IMEDIATAMENTE antes de olhar o Redis.
            $sLista = Status ($Gateway + '/api/jogos') 'GET' $null $token
            $chaves = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli keys 'catalog:*' 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
            'GET /api/jogos (aquece o cache) = ' + $sLista
            'redis-cli keys catalog:* = ' + $(if ($chaves) { $chaves } else { '(vazio)' })
            Chk ($chaves -match 'catalog:') 'redis-com-chaves-catalog'
            $tipo = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli type catalog:games:all 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
            $ttl = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli ttl catalog:games:all 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
            'redis-cli type/ttl catalog:games:all = ' + $tipo + ' / ' + $ttl + '  (esperado hash / ate 60)'
            $mCatalog = Metricas 'catalog-api:80'
            Chk ($mCatalog -match '(?m)^cache_hit') 'metrics-catalog-api-cache-hit'
            Chk ($mCatalog -match '(?m)^cache_miss') 'metrics-catalog-api-cache-miss'
        } elseif ($Modulo -eq 6) {
            Step 'MODULO 6 - repositorios e fechamento'
            $raizRepo = Split-Path -Parent $PSScriptRoot
            $paiDosRepos = Split-Path -Parent $raizRepo
            'repositorios locais = ' + $paiDosRepos
            # 1) Os 5 repositorios da tabela do README sem alteracao pendente (nada de arquivo modificado
            #    aparecendo na tela). Arquivo NAO RASTREADO nao e alteracao pendente: sai como ATENCAO.
            foreach ($repo in @('fcg-orchestration', 'fcg-users-api', 'fcg-catalog-api', 'fcg-payments-api', 'fcg-notifications-function')) {
                $caminho = Join-Path $paiDosRepos $repo
                $rotulo = 'repo-' + $repo + '-sem-alteracoes-pendentes'
                if (-not (Test-Path $caminho)) {
                    Write-Output ('FALHOU: o repositorio local ' + $caminho + ' nao existe -- a tabela do video cita os 5.')
                    Chk $false $rotulo
                    continue
                }
                $linhas = @(git -C $caminho status --porcelain 2>&1 | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' })
                $modificados = @($linhas | Where-Object { $_ -notmatch '^\?\?' })
                $naoRastreados = @($linhas | Where-Object { $_ -match '^\?\?' })
                'git status em ' + $repo + ' = ' + $(if ($linhas.Count -eq 0) { '(limpo)' } else { $modificados.Count.ToString() + ' com alteracao, ' + $naoRastreados.Count.ToString() + ' nao rastreado(s)' })
                if ($modificados.Count -gt 0) {
                    $modificados | Select-Object -First 8 | ForEach-Object { '  ' + $_ }
                }
                Chk ($modificados.Count -eq 0) $rotulo
                if (($naoRastreados.Count -gt 0) -and ($modificados.Count -eq 0)) {
                    Write-Output 'ATENCAO: ha arquivo NAO RASTREADO nesse repositorio (nao e alteracao pendente, mas aparece'
                    Write-Output 'ATENCAO: num git status na tela): confira antes de gravar.'
                    Write-Output '(esta situacao NAO entra na contagem de checagens: nao e alteracao pendente)'
                }
            }
            # 2) A evidencia de segredos do README (varios -e, nunca -E com alternancia e pipe escapado --
            #    dentro de tabela Markdown o \| e pipe LITERAL no regex do -E e a prova sairia vazia mesmo
            #    com vazamento). Os padroes sao montados por concatenacao de proposito: escritos inteiros
            #    aqui, ESTE arquivo seria encontrado pela propria evidencia. O resultado nunca e impresso
            #    linha a linha -- so a contagem, porque uma linha encontrada E um segredo.
            $argsGrep = @('-n', '-E')
            foreach ($padrao in @(('Password=' + 'FCG@'), ('Fcg2024' + 'Test!'), ('fcg-secret-key' + '-2024'))) { $argsGrep += @('-e', $padrao) }
            $argsGrep += @('--', '.', ':!README.md')
            $evidencia = @(git -C $raizRepo grep @argsGrep 2>&1 | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\S' })
            'evidencia de segredos (a mesma do README, com varios -e) = ' + $(if ($evidencia.Count -eq 0) { '(vazio: nenhuma credencial versionada)' } else { ($evidencia.Count.ToString() + ' linha(s) encontrada(s)') })
            Chk ($evidencia.Count -eq 0) 'evidencia-de-segredos-vazia'
            if ($evidencia.Count -gt 0) {
                Write-Output 'NAO GRAVE: a evidencia nao esta vazia. As linhas NAO sao impressas de proposito (uma linha'
                Write-Output 'encontrada aqui E a propria credencial): rode o mesmo git grep na sua maquina e corrija.'
            }
            # 3) O README que a tomada mostra: a tabela dos 5 repositorios (com o link da funcao) e a secao
            #    que mapeia requisito -> onde esta -> como comprovar.
            $caminhoReadme = Join-Path $raizRepo 'README.md'
            $temLinkFuncao = $false
            $temSecaoRequisitos = $false
            if (Test-Path $caminhoReadme) {
                $temLinkFuncao = [bool](Select-String -Path $caminhoReadme -Pattern 'gustavoaa-dev/fcg-notifications-function' -SimpleMatch -Quiet)
                $temSecaoRequisitos = [bool](Select-String -Path $caminhoReadme -Pattern '^## Atendimento dos requisitos da Fase 3' -Quiet)
            } else {
                Write-Output ('FALHOU: nao encontrei ' + $caminhoReadme + ' (e ele que a tomada mostra).')
            }
            'README com o link da funcao = ' + $temLinkFuncao + '  com a secao de requisitos = ' + $temSecaoRequisitos
            Chk $temLinkFuncao 'readme-com-link-do-repositorio-da-funcao'
            Chk $temSecaoRequisitos 'readme-com-secao-de-requisitos-da-fase-3'
        }
    } catch {
        Write-Output ''
        Write-Output ('ERRO NAO TRATADO: ' + (San $_.Exception.Message))
        Write-Output (San $_.ScriptStackTrace)
        $script:falhas++
    } finally {

        Step 'RESULTADO'
        'modulo=' + $Modulo + '  checagens=' + $script:checagens + '  falhas=' + $script:falhas
        if ($script:falhas -gt 0) {
            Write-Output ('PREFLIGHT REPROVADO: ' + $script:falhas + ' checagem(ns) falhou(aram) -- leia as linhas [FALHOU] acima.')
            Write-Output ('NAO GRAVE ainda o modulo ' + $Modulo + ': qualquer falha aqui aparece no video como um bloco sem evidencia.')
        } else {
            Write-Output ('TUDO PRONTO PARA GRAVAR O MODULO ' + $Modulo)
            if ($Modulo -eq 1) {
                Write-Output '  abra o README.md na secao Arquitetura (tabela de servicos + fluxo de eventos): e a tela da abertura'
                Write-Output '  nenhum recurso do cluster foi consumido por este preparo'
            } elseif ($Modulo -eq 2) {
                Write-Output ('  usuario de demonstracao: ' + $Email + ' (senha em FCG_DEMO_SENHA; a tomada faz login com ele)')
                Write-Output '  a Admin API (porta 8001) e DESTA tomada: suba o port-forward no T3 e feche-o ao terminar'
            } elseif ($Modulo -eq 3) {
                Write-Output ('  funcao de notificacoes: ' + $repFn + ' replicas e ' + $podsFn.Count + ' pod(s) -- a tomada comeca com o 0/0 na tela')
                Write-Output '  o cadastro da tomada sobe o pod em ~15-30s (pollingInterval de 15s; medido 20-31s)'
                Write-Output '  painel da tomada: Grafana > Dashboards > FCG - Logs (Loki), com o periodo Last 5 minutes'
            } elseif ($Modulo -eq 4) {
                if ($jogoDaTomada) {
                    Write-Output ('  jogo do modulo 4 (compra) = ' + $jogoDaTomadaNome + ' (' + $jogoDaTomada + ')')
                    Write-Output ("  copie para a sessao da tomada: `$env:FCG_DEMO_JOGO = '" + $jogoDaTomada + "'")
                }
                Write-Output '  painel da tomada: dashboard FCG - APIs em tela cheia + Status > Targets no Prometheus'
            } elseif ($Modulo -eq 5) {
                if ($jogoDaTomada) {
                    Write-Output ('  jogo do modulo 5 (avaliacoes) = ' + $jogoDaTomadaNome + ' (' + $jogoDaTomada + ')')
                    Write-Output ("  copie para a sessao da tomada: `$env:FCG_DEMO_JOGO = '" + $jogoDaTomada + "'")
                }
                Write-Output '  o PUT da tomada devolve 200 (upsert): este preparo ja gravou a avaliacao do demo neste jogo'
            } elseif ($Modulo -eq 6) {
                Write-Output '  os 5 repositorios locais estao sem alteracao pendente e a evidencia de segredos devolve vazio'
                Write-Output '  README com a tabela dos repositorios e a secao Atendimento dos requisitos da Fase 3'
            }
            Write-Output '  roteiro: docs/roteiro-video-fase3.md'
        }
        # O temporario guarda o corpo do login/cadastro com a senha da demo em claro: apagar SEMPRE.
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        'ambiente temporario removido'
    }

    exit $(if ($script:falhas -gt 0) { 1 } else { 0 })
}

$token = $null
try {

Step 'P1 - cluster: pods e PVCs'
'pods do namespace:'
kubectl get -n $namespace pods --no-headers 2>&1 | ForEach-Object { '  ' + $_ }
foreach ($app in @('sqlserver', 'rabbitmq', 'mongo', 'redis', 'users-api', 'catalog-api', 'payments-api', 'kong', 'prometheus', 'grafana', 'loki')) {
    Chk ((Prontos ('app=' + $app)) -ge 1) ('pod-' + $app + '-1/1-Running')
}
# O promtail e DaemonSet: um pod por no (neste cluster, 1). Sem ele nao ha log no Loki.
Chk ((Prontos 'app=promtail') -ge 1) 'pod-promtail-1/1-Running'
'pvc do cluster:'
$linhasPvc = @(kubectl get -n $namespace pvc --no-headers 2>&1)
$linhasPvc | ForEach-Object { '  ' + $_ }
foreach ($pvc in @('mongo-data', 'sqlserver-data', 'rabbitmq-data', 'prometheus-data')) {
    $l = @($linhasPvc | Where-Object { $_ -match ('^' + [regex]::Escape($pvc) + '\s') })
    Chk (($l.Count -ge 1) -and ($l[0] -match '\sBound\s')) ('pvc-' + $pvc + '-Bound')
}

Step 'P2 - gateway sem token'
$s401 = Status ($Gateway + '/api/jogos') 'GET' $null $null
'GET /api/jogos sem token = ' + $s401 + '  (esperado 401)'
Chk ($s401 -eq '401') 'gateway-401-sem-token'

Step 'P3 - usuario de demonstracao'
'email de demonstracao = ' + $Email + '  (a senha vem de FCG_DEMO_SENHA e nao e impressa)'
$script:ultimoLogin = ''
$token = Token
'POST /api/auth/login = ' + $script:ultimoLogin + '  (esperado 200)'
if (-not $token) {
    'login falhou: criando o usuario de demonstracao pelo gateway (POST /api/usuarios)...'
    $bCad = Body 'cadastro-demo.json' ('{"nome":"' + $Nome + '","email":"' + $Email + '","senha":"' + $Senha + '"}')
    $rCad = Resposta ($Gateway + '/api/usuarios') 'POST' $bCad $null
    'POST /api/usuarios = ' + $rCad.Code + '  (esperado 201)'
    if ($rCad.Code -eq '400') {
        'ATENCAO: o cadastro respondeu 400 -- o e-mail ja existe com OUTRA senha (o login falhou)'
        'ou a senha nao atende a politica (8+ caracteres, com letra, digito e caractere especial).'
    }
    $token = Token
    if ($token) {
        Write-Output '*** AVISO: o usuario de demonstracao NAO existia e foi CRIADO agora pelo preflight. ***'
        Write-Output '*** AVISO: a criacao publica UserCreatedEvent e acorda a funcao serverless; este script ***'
        Write-Output '*** AVISO: espera o cooldown no P11 para a gravacao comecar com a funcao em 0 replicas. ***'
    }
}
Chk ([bool]$token) 'usuario-de-demonstracao-login-200'
if ($token) { 'token obtido: ' + $token.Length + ' caracteres (valor nunca e impresso)' }

Step 'P4 - gateway com token'
$s200 = Status ($Gateway + '/api/jogos') 'GET' $null $token
'GET /api/jogos com token = ' + $s200 + '  (esperado 200)'
Chk ($s200 -eq '200') 'gateway-200-com-token'

Step 'P5 - Prometheus: alvos do job fcg-apis'
$alvos = $null
try { $alvos = ((kubectl get --raw ('/api/v1/namespaces/' + $namespace + '/services/prometheus:9090/proxy/api/v1/targets') 2>&1) | Out-String | ConvertFrom-Json) } catch { $alvos = $null }
if ($alvos) {
    # O Where-Object nao e enfeite: sem ele, um campo ausente na resposta vira @($null), que o
    # PowerShell conta como UM elemento e faria a checagem passar sem ter lido alvo nenhum.
    $ativos = @($alvos.data.activeTargets | Where-Object { $_ -ne $null })
    foreach ($t in $ativos) { '  alvo job=' + $t.labels.job + ' ' + $t.scrapeUrl + ' health=' + $t.health }
    $fcg = @($ativos | Where-Object { $_.labels.job -eq 'fcg-apis' })
    Chk ($fcg.Count -eq 3) 'prometheus-tres-alvos-fcg-apis'
    foreach ($api in @('users-api', 'catalog-api', 'payments-api')) {
        Chk ([bool](@($fcg | Where-Object { $_.scrapeUrl -match ($api + ':80') -and $_.health -eq 'up' }))) ('prometheus-alvo-' + $api + '-up')
    }
    Chk ((@($ativos | Where-Object { $_.health -ne 'up' }).Count) -eq 0) 'prometheus-nenhum-alvo-down'
} else {
    'PROMETHEUS INACESSIVEL pelo proxy do kubectl (get --raw .../services/prometheus:9090/proxy/api/v1/targets)'
    Chk $false 'prometheus-tres-alvos-fcg-apis'
}

Step 'P6 - Loki: pronto e com log da stack'
$ready = (Kraw ('/api/v1/namespaces/' + $namespace + '/services/loki:3100/proxy/ready')).Trim()
'loki /ready = ' + $ready + '  (esperado ready)'
# -eq e nao -match: um Loki AINDA NAO pronto responde 503 com "ingester not ready: waiting for 15s
# after being ready" -- a palavra "ready" esta no meio da mensagem e o -match aprovaria um Loki fora.
Chk ($ready -eq 'ready') 'loki-ready'
# O teste mais simples de "este app tem log no Loki" e a lista de valores do rotulo app: nao depende
# de janela de tempo e nao cai na armadilha da query instantanea
# (/loki/api/v1/query recusa log query com "400 log queries are not supported as an instant query type").
$rotulos = @()
for ($i = 0; $i -lt 4; $i++) {
    try {
        $resp = (Kraw ('/api/v1/namespaces/' + $namespace + '/services/loki:3100/proxy/loki/api/v1/label/app/values'))
        $lido = ($resp | ConvertFrom-Json).data
        # @($null) conta como UM elemento no PowerShell: o filtro evita aprovar sem ter lido nada.
        $rotulos = @($lido | Where-Object { $_ -ne $null })
    } catch { $rotulos = @() }
    if ($rotulos.Count -gt 0) { break }
    Start-Sleep -Seconds 5
}
'rotulos app no Loki = ' + $(if ($rotulos.Count -gt 0) { $rotulos -join ', ' } else { '(nenhum)' })
Chk ($rotulos.Count -ge 1) 'loki-rotulo-app-com-log'
# A checagem do log da FUNCAO era o proprio rotulo ($temLogDaFuncao) -- e isso e TAUTOLOGIA: o Chk so
# existia no ramo em que o predicado ja era verdadeiro, entao nao podia reprovar nada e ainda inflava a
# contagem (achado I4 da revisao final). Agora o ramo do rotulo presente busca LINHAS de verdade na
# janela de 24h: /loki/api/v1/label/app/values prova que o cliente funciona, mas as LINHAS vem do
# query_range (start/end em epoch de SEGUNDOS). Este ramo PODE falhar -- rotulo presente e nenhuma linha
# legivel -- e e exatamente para isso que ele existe. O ramo do rotulo ausente continua ATENCAO, sem
# [OK] e sem contar: o rotulo so nasce depois que a funcao sobe uma vez na retencao de 24h.
$temLogDaFuncao = ($rotulos -contains 'notifications-function')
if ($temLogDaFuncao) {
    # O filtro vai URL-encoded ({app="notifications-function"} tem chaves e aspas, que o PowerShell 5.1
    # nao entrega inteiras em argumento de processo nativo -- mesma armadilha do sqlcmd). O `&` dos
    # parametros e seguro: o comando e chamado direto, sem cmd no meio.
    $agoraLoki = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $caminhoLinhas = ('/api/v1/namespaces/' + $namespace + '/services/loki:3100/proxy/loki/api/v1/query_range?query=%7Bapp%3D%22notifications-function%22%7D&limit=20&start=' + ($agoraLoki - 86400) + '&end=' + $agoraLoki)
    $linhasFuncao = 0
    $respostaLinhas = ''
    try {
        $respostaLinhas = Kraw $caminhoLinhas
        $jsonLinhas = ($respostaLinhas | ConvertFrom-Json)
        # @($null) conta como UM elemento: sem o filtro, uma resposta sem 'result' viraria 1 "linha".
        foreach ($fluxo in @($jsonLinhas.data.result | Where-Object { $_ -ne $null })) {
            if ($fluxo.values) { $linhasFuncao += @($fluxo.values | Where-Object { $_ -ne $null }).Count }
        }
    } catch { $linhasFuncao = 0 }
    'linhas de notifications-function na janela de 24h = ' + $linhasFuncao + '  (esperado >= 1)'
    if ($linhasFuncao -lt 1) {
        Write-Output 'FALHOU: o rotulo notifications-function existe no Loki, mas nenhuma LINHA foi lida na'
        Write-Output 'FALHOU: janela de 24h -- o painel de logs do bloco 3 nao teria o que mostrar. Remedio:'
        Write-Output 'FALHOU: um cadastro pelo gateway gera uma linha nova; se ainda assim nao aparecer, confira'
        Write-Output 'FALHOU: o Promtail (k8s/promtail-deployment.yaml), que e quem coleta o log dos pods.'
        $amostraLinhas = (San ((([string]$respostaLinhas) -replace '\s+', ' '))).Trim()
        if ($amostraLinhas.Length -gt 300) { $amostraLinhas = $amostraLinhas.Substring(0, 300) }
        Write-Output ('  resposta do Loki (resumida) = ' + $(if ($amostraLinhas) { $amostraLinhas } else { '(vazia)' }))
    }
    Chk ($linhasFuncao -ge 1) 'loki-log-da-funcao-de-notificacoes'
} else {
    Write-Output 'ATENCAO: ainda nao ha log de notifications-function no Loki (a funcao nao rodou nas'
    Write-Output 'ATENCAO: ultimas 24h). Faca um cadastro pelo gateway e confira de novo; o bloco'
    Write-Output 'ATENCAO: serverless do video gera esse log ao vivo e o painel do Grafana mostra ele.'
    Write-Output '(esta situacao NAO entra na contagem de checagens: nao ha o que verificar ainda)'
}

Step 'P7 - Grafana: saude, datasources e dashboards'
# A senha do Secret e lida em memoria por dois motivos: diagnostico (sem ela o container tambem esta
# sem GF_SECURITY_ADMIN_PASSWORD e o pod nem sobe) e a lista de segredos que o San() mascara. Ela NAO
# e mais necessaria para consultar a API -- desde a correcao do I3 quem autentica e o shell DENTRO do
# pod, com a variavel do proprio ambiente --, entao uma leitura falha do Secret nao reprova sozinha:
# quem reprova e a resposta da API (e essa leitura nao curto-circuita mais as cinco checagens abaixo).
$script:senhaGrafana = SecretValor 'grafana-admin' 'admin-password'
if ($script:senhaGrafana) {
    $script:segredos += $script:senhaGrafana
    # As DUAS formas da senha entram na lista: a crua e a escapada ([uri]::EscapeDataString). A forma
    # escapada nao viaja em saida nenhuma depois do I3, mas manter as duas e uma linha e a lista de
    # segredos e o unico ponto de defesa da saida -- mais barato que uma senha no relatorio.
    $script:segredos += [uri]::EscapeDataString($script:senhaGrafana)
} else {
    Write-Output 'nao consegui ler o Secret grafana-admin/admin-password: a consulta abaixo NAO depende'
    Write-Output 'dele (quem autentica e o $GF_SECURITY_ADMIN_PASSWORD do container). Se o Secret faltar,'
    Write-Output 'o pod do Grafana nem sobe -- o que a checagem do P1 pega.'
}
$health = $null
try { $health = (GrafanaApi '/api/health' | ConvertFrom-Json) } catch { $health = $null }
'grafana /api/health = ' + $(if ($health) { 'database=' + $health.database + ' version=' + $health.version } else { '(sem resposta)' })
Chk ($health -and $health.database -eq 'ok') 'grafana-health-ok'
$ds = @()
try { $ds = @(GrafanaApi '/api/datasources' | ConvertFrom-Json) } catch { $ds = @() }
'datasources = ' + $(if ($ds.Count -gt 0) { (@($ds | ForEach-Object { $_.uid }) -join ', ') } else { '(nenhum)' })
Chk ((@($ds | Where-Object { $_.uid -eq 'loki' }).Count) -ge 1) 'grafana-datasource-loki'
Chk ((@($ds | Where-Object { $_.uid -eq 'prometheus' }).Count) -ge 1) 'grafana-datasource-prometheus'
$dash = @()
try { $dash = @(GrafanaApi '/api/search?query=FCG' | ConvertFrom-Json) } catch { $dash = @() }
$uids = @($dash | ForEach-Object { $_.uid })
'dashboards encontrados = ' + $(if ($uids.Count -gt 0) { $uids -join ', ' } else { '(nenhum)' })
Chk ($uids -contains 'fcg-apis') 'grafana-dashboard-fcg-apis'
Chk ($uids -contains 'fcg-logs') 'grafana-dashboard-fcg-logs'

Step 'P8 - KEDA: filas do broker e ScaledObject'
$filas = (San (((kubectl exec -n $namespace deploy/rabbitmq -- rabbitmqctl list_queues name 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
$filas -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object { '  ' + $_.Trim() }
foreach ($fila in @('notifications-user-created', 'notifications-payment-processed', 'notifications-dead-letter')) {
    Chk ($filas -match [regex]::Escape($fila)) ('fila-' + $fila)
}
$so = $null
try { $so = (kubectl get -n $namespace scaledobject notifications-function -o json 2>&1 | Out-String | ConvertFrom-Json) } catch { $so = $null }
if ($so) {
    $readySo = ($so.status.conditions | Where-Object { $_.type -eq 'Ready' }).status
    'ScaledObject notifications-function Ready=' + $readySo + '  min=' + $so.spec.minReplicaCount + ' max=' + $so.spec.maxReplicaCount
    Chk ($readySo -eq 'True') 'scaledobject-Ready-True'
    if ($readySo -ne 'True') {
        'TriggerError costuma ser fila ausente no broker: rode o terraform apply do repositorio da funcao.'
        San (((kubectl describe -n $namespace scaledobject notifications-function 2>&1) | Select-String -Pattern 'Ready|Error|queue' | Select-Object -First 8 | ForEach-Object { '  ' + [string]$_ }) -join "`n")
    }
} else {
    'ScaledObject notifications-function nao encontrado: a funcao nao esta implantada (terraform apply do repo dela)'
    Chk $false 'scaledobject-Ready-True'
}

Step 'P9 - dados de demonstracao: jogos no catalogo e o jogo do bloco 4'
$lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
$jogos = @($lista.Body | Where-Object { $_ -ne $null })
'GET /api/jogos = ' + $lista.Code + '  jogos no catalogo = ' + $jogos.Count + '  (minimo ' + $JogosMinimos + ')'
# A checagem do catalogo tambem exige PARSE (mesma classe do I2 na biblioteca, e aqui o efeito
# colateral seria pior): um 200 de corpo ilegivel vira "catalogo vazio" e o preflight comecaria a
# PROMOVER o usuario a Admin e a CRIAR jogos a partir de um corpo que ele nao conseguiu ler.
# Com ParseOk no predicado, o corpo ilegivel reprova aqui e nada e criado a partir dele.
Chk ($lista.Code -eq '200' -and $lista.ParseOk) 'catalogo-listagem-200'
if (-not $lista.ParseOk) {
    Write-Output ('FALHOU: GET /api/jogos respondeu ' + $lista.Code + ' com um corpo que NAO deu para ler como')
    Write-Output ('FALHOU: JSON (' + ([string]$lista.Texto).Length + ' caractere(s)): nao ha catalogo para escolher o jogo do')
    Write-Output 'FALHOU: bloco 4, e NADA sera criado a partir deste corpo.'
    $amostraCatalogo = (San ((([string]$lista.Texto) -replace '\s+', ' '))).Trim()
    if ($amostraCatalogo.Length -gt 300) { $amostraCatalogo = $amostraCatalogo.Substring(0, 300) }
    if ($amostraCatalogo) { Write-Output ('FALHOU: inicio do corpo recebido = ' + $amostraCatalogo) }
} elseif ($jogos.Count -lt $JogosMinimos) {
    Write-Output '*** AVISO: faltam jogos para a demonstracao (o dado do SQL Server e volatil enquanto o ***'
    Write-Output '*** AVISO: PVC nao entrar: qualquer restart de container esvazia o banco). Criando agora. ***'
    # O POST /api/jogos exige Admin e a users-api registra todos como Usuario: promocao direta no SQL.
    # A promocao usa PromoverDemoAdmin(): SQL por STDIN -> /tmp -> "sqlcmd -i" -> "rm", sem aspas
    # internas, e CONFERE o Role depois do UPDATE (um SQL truncado nao promoveria ninguem e o login
    # continuaria 200, porque ele funciona com qualquer role).
    # A senha do sa nao entra em argv nenhum: o shell do container expande o $SA_PASSWORD que o pod ja
    # tem no ambiente (secretKeyRef do sqlserver-secret, em k8s/sqlserver-deployment.yaml).
    $sa = SecretValor 'sqlserver-secret' 'sa-password'
    # O Secret ainda e lido em memoria: se ele nao existir, o container tambem esta sem SA_PASSWORD e o
    # sqlcmd falharia de um jeito confuso -- melhor reprovar aqui, com a causa.
    Chk ([bool]$sa) 'secret-sqlserver-sa-password-presente'
    if (-not $sa) {
        'NAO consegui ler o Secret sqlserver-secret/sa-password: o POST de jogo vai responder 403.'
    } else {
        $script:segredos += $sa
        $promo = PromoverDemoAdmin $Email
        'promocao do usuario de demonstracao a Admin (sqlcmd -i dentro do pod, com $SA_PASSWORD do ambiente):'
        $(if ($promo.Saida) { '  ' + $promo.Saida } else { '  (sem saida)' })
        'Role lido do SQL depois do UPDATE = [' + ($promo.Role -replace "`r?`n", ' ') + ']  (esperado 1)'
        Chk ($promo.Role -match '(?m)^\s*1\s*$') 'promocao-role-1-no-sql'
        $token = Token
        Chk ([bool]$token) 'login-apos-promocao-a-Admin'
    }
    # Cria jogos ate o minimo, re-listando a cada criacao (o POST devolve 201 e o catalogo cresce).
    $tentativaJogo = 0
    while (($jogos.Count -lt $JogosMinimos) -and ($tentativaJogo -lt 6)) {
        $tentativaJogo++
        $nomeJogo = 'Jogo Demo ' + $tentativaJogo
        $bJogo = Body ('jogo-' + $tentativaJogo + '.json') ('{"nome":"' + $nomeJogo + '","descricao":"Jogo de demonstracao da Fase 3","preco":' + (49 + $tentativaJogo) + '.90}')
        $rJogo = Resposta ($Gateway + '/api/jogos') 'POST' $bJogo $token
        'POST /api/jogos = ' + $rJogo.Code + '  (esperado 201)  nome=' + $nomeJogo
        if ($rJogo.Code -ne '201') { break }
        $lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
        $jogos = @($lista.Body | Where-Object { $_ -ne $null })
    }
    'jogos no catalogo apos a criacao = ' + $jogos.Count
}
Chk ($jogos.Count -ge $JogosMinimos) 'catalogo-com-jogos-para-a-demo'

# O BLOCO 4 DO VIDEO COMPRA UM JOGO -- e so a PRIMEIRA compra daquele par (usuario, jogo) devolve 202 e
# move o painel de pagamentos. O catalogo do cluster volta ORDENADO POR NOME (nao por criacao) e a
# biblioteca do usuario de demonstracao cresce a cada rodada, entao "o primeiro id do catalogo" nao
# serve: o jogo tem de ser o primeiro que o usuario AINDA NAO possui. A escolha e impressa no
# RESULTADO para o roteiro usar exatamente ela.
$userId = Claim $token 'Id'
'userId (claim Id do token) = ' + $userId
$bib = Resposta ($Gateway + '/api/biblioteca/' + $userId) 'GET' $null $token
'GET /api/biblioteca/{userId} = ' + $bib.Code + '  (a biblioteca do usuario demo)'
$idsBiblioteca = @()
# Mesma politica do rotulo do Loki: o predicado vai para o Chk (nunca uma constante -- o [OK] tem de
# vir da verificacao). E a mesma regra da compra: so a variacao LEGITIMA de estado vira ATENCAO --
# 404 = "este usuario ainda nao tem biblioteca" (nada possuido, a escolha continua valida); qualquer
# outro codigo (401/403/500/000) e FALHA de verdade, porque sem a biblioteca a escolha do jogo do
# bloco 4 poderia mentir.
$bibliotecaLida = ($bib.Code -eq '200')
$bibliotecaVazia = ($bib.Code -eq '404')
if ($bibliotecaLida) {
    $itensBiblioteca = @(ItensDaBiblioteca $bib.Body)
    $idsBiblioteca = @(IdsDaBiblioteca $bib.Body | ForEach-Object { ([string]$_).ToLower() })
    # A checagem NAO pode dar [OK] so pelo transporte -- nem por um corpo que nem e JSON:
    #   * 200 com itens e ZERO ids reconhecidos e QUEBRA DE CONTRATO (foi assim que a escolha errada
    #     saiu com a linha verde na rodada 2);
    #   * 200 com corpo ILEGIVEL (ParseOk = $false: HTML de proxy, texto solto) ou VAZIO (corpo de 0
    #     caractere, que o ConvertFrom-Json do 5.1 aceita calado devolvendo $null) e o buraco que a
    #     revisao final mediu: o catch do Partir devolvia Body = $null, o extrator lia "lista vazia",
    #     a escolha do bloco 4 caia no primeiro jogo do catalogo SEM verificacao e as DUAS checagens
    #     saiam verdes. Por isso o ParseOk entra no predicado;
    #   * lista vazia PARSEADA (200 com "[]") continua sendo o caso LEGITIMO de "usuario sem jogos" --
    #     a API responde Ok(lista) (BibliotecaController), entao o caso vazio sai como "[]" no corpo:
    #     corpo vazio/ilegivel nao e contrato valido, so a lista vazia de verdade e.
    $bibliotecaInterpretavel = ($bib.ParseOk -and (($itensBiblioteca.Count -eq 0) -or ($idsBiblioteca.Count -eq $itensBiblioteca.Count)))
    'biblioteca do usuario demo = ' + $itensBiblioteca.Count + ' item(ns), ' + $idsBiblioteca.Count + ' id(s) reconhecido(s)'
    if (-not $bib.ParseOk) {
        $corpoVazio = [string]::IsNullOrWhiteSpace([string]$bib.Texto)
        Write-Output ('FALHOU: a biblioteca respondeu 200 com ' + $(if ($corpoVazio) { 'corpo VAZIO' } else { 'um corpo que NAO e JSON' }) + ' (' + ([string]$bib.Texto).Length + ' caractere(s)).')
        Write-Output 'FALHOU: sem o parse nao da para distinguir "o usuario nao possui jogos" de "o corpo nao'
        Write-Output 'FALHOU: foi lido": ate a revisao final esse corpo virava lista VAZIA, a escolha do bloco'
        Write-Output 'FALHOU: 4 saia no escuro e as duas checagens ficavam verdes.'
        if (-not $corpoVazio) {
            $amostraBib = (San ((([string]$bib.Texto) -replace '\s+', ' '))).Trim()
            if ($amostraBib.Length -gt 300) { $amostraBib = $amostraBib.Substring(0, 300) }
            Write-Output ('FALHOU: inicio do corpo recebido = ' + $amostraBib)
        }
    } elseif ($bibliotecaInterpretavel) {
        if ($itensBiblioteca.Count -gt 0) { 'ids da biblioteca = ' + ($idsBiblioteca -join ', ') }
        else { '(lista vazia: o usuario nao possui nenhum jogo)' }
    } else {
        Write-Output ('FALHOU: a biblioteca respondeu 200 com ' + $itensBiblioteca.Count + ' item(ns), mas a extracao')
        Write-Output ('FALHOU: reconheceu ' + $idsBiblioteca.Count + ' id(s) -- quebra de contrato no corpo.')
        if ($script:camposBiblioteca) {
            Write-Output ('FALHOU: campos do item da biblioteca: ' + $script:camposBiblioteca)
        }
        Write-Output 'FALHOU: o contrato medido no cluster usa "gameId"; sem os ids a escolha do bloco 4'
        Write-Output 'FALHOU: fica no escuro (foi o defeito da rodada 2).'
    }
    Chk $bibliotecaInterpretavel 'biblioteca-do-usuario-200'
} elseif ($bibliotecaVazia) {
    Write-Output 'ATENCAO: GET /api/biblioteca/{userId} respondeu 404: o usuario de demonstracao ainda nao'
    Write-Output 'ATENCAO: tem biblioteca (nada possuido), entao a escolha abaixo cai no PRIMEIRO jogo do'
    Write-Output 'ATENCAO: catalogo -- que nesse caso e o correto, porque ele nao possui nenhum.'
    Write-Output '(esta situacao NAO entra na contagem de checagens: e estado legitimo, nao falha)'
} else {
    Write-Output ('FALHOU: GET /api/biblioteca/{userId} devolveu ' + $bib.Code + ' -- a biblioteca do usuario')
    Write-Output 'FALHOU: de demonstracao nao pode ser lida, e sem ela a escolha do jogo do bloco 4 pode'
    Write-Output 'FALHOU: cair em um jogo que ele ja possui (compra 400 no video).'
    Chk $false 'biblioteca-do-usuario-200'
}
$jogoDemo = $null
$jogoDemoNome = ''
$tentativaLivre = 0
while ((-not $jogoDemo) -and ($tentativaLivre -lt 3)) {
    $tentativaLivre++
    for ($i = 0; $i -lt $jogos.Count; $i++) {
        $idCand = [string]$jogos[$i].id
        if ($idCand -and ($idsBiblioteca -notcontains $idCand.ToLower())) {
            $jogoDemo = $idCand
            $jogoDemoNome = [string]$jogos[$i].nome
            break
        }
    }
    if (-not $jogoDemo) {
        # Todos os jogos do catalogo ja estao na biblioteca: cria mais um e recalcula. O POST exige
        # Admin -- se este preflight ainda nao promoveu o usuario (o catalogo ja tinha 3 jogos, entao o
        # caminho da promocao nao rodou), promove agora e tenta de novo: sem isso a gravacao ficaria
        # sem nenhum jogo livre para o bloco 4.
        'todos os jogos do catalogo ja estao na biblioteca do usuario demo: criando mais um'
        $nomeExtra = 'Jogo Demo Livre ' + $tentativaLivre
        $bExtra = Body ('jogo-extra-' + $tentativaLivre + '.json') ('{"nome":"' + $nomeExtra + '","descricao":"Jogo livre para a compra do video","preco":89.90}')
        $rExtra = Resposta ($Gateway + '/api/jogos') 'POST' $bExtra $token
        'POST /api/jogos = ' + $rExtra.Code + '  (esperado 201)  nome=' + $nomeExtra
        if ($rExtra.Code -ne '201') {
            $saExtra = SecretValor 'sqlserver-secret' 'sa-password'
            if ($saExtra) {
                $script:segredos += $saExtra
                'POST recusado (' + $rExtra.Code + '): promovendo o usuario demo a Admin e tentando de novo'
                $promoExtra = PromoverDemoAdmin $Email
                $(if ($promoExtra.Saida) { '  ' + $promoExtra.Saida } else { '  (sem saida)' })
                'Role lido do SQL depois do UPDATE = [' + ($promoExtra.Role -replace "`r?`n", ' ') + ']  (esperado 1)'
                $token = Token
                $rExtra = Resposta ($Gateway + '/api/jogos') 'POST' $bExtra $token
                'POST /api/jogos (apos a promocao) = ' + $rExtra.Code + '  (esperado 201)'
            } else {
                'NAO consegui ler o Secret sqlserver-secret/sa-password: nao ha como promover o usuario'
            }
            if ($rExtra.Code -ne '201') { break }
        }
        $lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
        $jogos = @($lista.Body | Where-Object { $_ -ne $null })
    }
}
'jogo do bloco 4 (compra) = ' + $jogoDemoNome + ' (' + $jogoDemo + ')'

# A checagem do jogo do bloco 4 e um PREDICADO REAL (o defeito da rodada 2 aprovou uma escolha errada
# -- mesma classe do [OK] constante que a rodada 1 mandou eliminar): o id escolhido tem de EXISTIR no
# catalogo e NAO estar na biblioteca LIDA. Se a biblioteca nao pode ser lida (Code != 200), nao ha como
# garantir a segunda metade: sai ATENCAO e a checagem NAO e contada (e, se o codigo foi diferente de
# 404, a checagem da biblioteca acima ja reprovou o preflight).
$idsCatalogo = @($jogos | ForEach-Object { ([string]$_.id).ToLower() })
$idEscolhido = ''
if ($jogoDemo) { $idEscolhido = ([string]$jogoDemo).ToLower() }
$existeNoCatalogo = [bool]($idEscolhido -and ($idsCatalogo -contains $idEscolhido))
if ($bibliotecaLida) {
    $estaNaBiblioteca = ($idsBiblioteca -contains $idEscolhido)
    $jogoLivre = [bool]($existeNoCatalogo -and (-not $estaNaBiblioteca))
    if ($estaNaBiblioteca) {
        Write-Output ('FALHOU: o jogo escolhido para o bloco 4 (' + $jogoDemo + ') ESTA na biblioteca do usuario')
        Write-Output 'FALHOU: demo -- a compra do video responderia 400. A escolha (primeiro do catalogo que'
        Write-Output 'FALHOU: ele nao possui) falhou: confira o extrator de ids da biblioteca acima.'
    }
    if (-not $existeNoCatalogo) {
        Write-Output ('FALHOU: o jogo escolhido (' + $jogoDemo + ') nao esta na lista do catalogo lida.')
    }
    'jogo do bloco 4 livre = ' + $jogoLivre + '  (existe no catalogo=' + $existeNoCatalogo + '  esta na biblioteca=' + $estaNaBiblioteca + ')'
    Chk $jogoLivre 'jogo-do-bloco-4-escolhido'
} else {
    if ($existeNoCatalogo) {
        Write-Output 'ATENCAO: sem a biblioteca lida nao da para garantir que o jogo escolhido esta livre'
        Write-Output ('ATENCAO: (ele existe no catalogo=' + $existeNoCatalogo + ', mas a posse nao foi verificada).')
        Write-Output '(esta situacao NAO entra na contagem de checagens: a posse nao pode ser verificada)'
    } else {
        Write-Output 'FALHOU: nenhum jogo valido foi escolhido para o bloco 4 (o id escolhido nao esta na'
        Write-Output 'FALHOU: lista do catalogo lida) -- o bloco 4 do video ficaria sem jogo para comprar.'
        Chk $false 'jogo-do-bloco-4-escolhido'
    }
}

Step 'P10 - Redis (cache) e MongoDB (avaliacoes)'
# O TTL da chave e de 60s: a listagem e lida IMEDIATAMENTE antes de olhar o Redis.
$sLista = Status ($Gateway + '/api/jogos') 'GET' $null $token
$chaves = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli keys 'catalog:*' 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
'GET /api/jogos (aquece o cache) = ' + $sLista
'redis-cli keys catalog:* = ' + $(if ($chaves) { $chaves } else { '(vazio)' })
Chk ($chaves -match 'catalog:') 'redis-com-chaves-catalog'
if ($jogoDemo) {
    $tipo = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli type catalog:games:all 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
    $ttl = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli ttl catalog:games:all 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
    'redis-cli type/ttl catalog:games:all = ' + $tipo + ' / ' + $ttl + '  (esperado hash / ate 60)'
    $mongo = Resposta ($Gateway + '/api/jogos/' + $jogoDemo + '/avaliacoes') 'GET' $null $token
    'GET /api/jogos/{id}/avaliacoes = ' + $mongo.Code + '  (esperado 200: e o caminho do Mongo)'
    Chk ($mongo.Code -eq '200') 'mongo-avaliacoes-200'
} else {
    'sem jogo escolhido: a checagem do Mongo nao pode rodar'
    Chk $false 'mongo-avaliacoes-200'
}

Step 'P10b - series dos paineis e os comandos de compra/avaliacao do video'
# Os paineis do dashboard FCG - APIs derivam destas series (as de cache tem o nome CRU, sem _total).
# As quatro series abaixo ja existem sem a compra: users-api e catalog-api atenderam o login, a
# listagem e a biblioteca deste proprio preflight, e cache_hit/cache_miss nascem no start do
# catalog-api. O CONTADOR DE PAGAMENTOS e outro caso -- ver o bloco depois da compra, logo abaixo
# (achado I1 da revisao final).
$mUsers = Metricas 'users-api:80'
$mCatalog = Metricas 'catalog-api:80'
Chk ($mUsers -match 'http_requests_received_total') 'metrics-users-api-http-requests'
Chk ($mCatalog -match 'http_requests_received_total') 'metrics-catalog-api-http-requests'
Chk ($mCatalog -match '(?m)^cache_hit') 'metrics-catalog-api-cache-hit'
Chk ($mCatalog -match '(?m)^cache_miss') 'metrics-catalog-api-cache-miss'
# A compra do preflight NAO usa o jogo do bloco 4: usa o ULTIMO jogo do catalogo que NAO seja ele.
# Motivo: o jogo escolhido no P9 e o que o video vai comprar, e so a PRIMEIRA compra daquele par
# (usuario, jogo) devolve 202 e move o painel de pagamentos -- consumindo-o aqui, o bloco 4 cairia em
# 400/409. Com o minimo de 3 jogos sempre existe outro candidato.
$jogoVerificacao = $null
for ($i = $jogos.Count - 1; $i -ge 0; $i--) {
    $idCand = [string]$jogos[$i].id
    if ($idCand -and ($idCand -ne $jogoDemo)) { $jogoVerificacao = $idCand; break }
}
$compraAceita = $false
$codCompra = ''
if ($userId -and $jogoVerificacao) {
    $bCompra = Body 'compra.json' ('{"userId":"' + $userId + '","gameId":"' + $jogoVerificacao + '"}')
    $rCompra = Resposta ($Gateway + '/api/jogos/' + $jogoVerificacao + '/comprar') 'POST' $bCompra $token
    $codCompra = $rCompra.Code
    'POST /api/jogos/{id}/comprar = ' + $rCompra.Code + '  (esperado 202)  jogo de verificacao=' + $jogoVerificacao
    '  corpo = ' + $rCompra.Texto
    # Tres desfechos, e SO um deles e sucesso:
    #   202        -> [OK]: e a compra ACEITA que publica OrderPlacedEvent e move o painel de pagamentos;
    #   400 / 409  -> ATENCAO sem contar: re-execucao legitima (o usuario ja possui este jogo) e o jogo
    #                 do bloco 4 nao e afetado, porque ele foi escolhido por NAO estar na biblioteca;
    #   QUALQUER OUTRO (401, 403, 500, 000...) -> FALHOU de verdade: o endpoint de compra nao esta
    #                 respondendo como esperado e o preflight NAO pode anunciar "pronto para gravar".
    # Repare no rigor: generalizar o "!= 202" para ATENCAO engoliria justamente os codigos que
    # denunciam um endpoint quebrado -- so a variacao LEGITIMA de estado vira ATENCAO.
    $compraAceita = ($rCompra.Code -eq '202')
    $compraReexecucao = (@('400', '409') -contains $rCompra.Code)
    if ($compraAceita) {
        Chk $compraAceita 'compra-aceita-202'
    } elseif ($compraReexecucao) {
        Write-Output ('ATENCAO: a compra de verificacao devolveu ' + $rCompra.Code + ' (o usuario de demonstracao')
        Write-Output 'ATENCAO: ja possui ESTE jogo). O que se perde aqui e apenas a evidencia de que o fluxo de'
        Write-Output 'ATENCAO: pagamento responde 202 nesta rodada.'
        # A frase sobre o bloco 4 so pode ser afirmada se a POSSE foi de fato verificada nesta rodada
        # (biblioteca lida e escolha conferida no P9): sem isso, ela orientaria mal o apresentador.
        if ($bibliotecaLida) {
            Write-Output 'ATENCAO: O bloco 4 do video NAO e afetado: o jogo dele foi escolhido no P9 por NAO estar'
            Write-Output 'ATENCAO: na biblioteca do demo -- e essa posse foi VERIFICADA nesta rodada (biblioteca lida).'
        } else {
            Write-Output 'ATENCAO: a biblioteca NAO foi lida nesta rodada, entao a posse do jogo do bloco 4'
            Write-Output 'ATENCAO: NAO foi verificada -- confira a biblioteca do demo antes de gravar.'
        }
        Write-Output '(esta situacao NAO entra na contagem de checagens: e re-execucao, nao falha)'
    } else {
        Write-Output ('FALHOU: a compra devolveu ' + $rCompra.Code + ' -- isso NAO e re-execucao (400/409):')
        Write-Output 'FALHOU: o endpoint POST /api/jogos/{id}/comprar nao esta respondendo como esperado'
        Write-Output 'FALHOU: (401 = token recusado, 403 = sem permissao, 5xx/000 = servico ou gateway fora).'
        Write-Output 'FALHOU: o bloco 4 do video depende deste endpoint.'
        Chk $false 'compra-aceita-202'
    }
} else {
    'sem userId no token ou sem jogo de verificacao: a compra do bloco 4 do video nao pode ser exercitada'
    Chk $false 'compra-aceita-202'
}
# O CONTADOR DE PAGAMENTOS E LIDO **DEPOIS** DA COMPRA (achado I1 da revisao final). No prometheus-net
# 8.2.1 uma familia COM LABELS nao cria filho nenhum ate o primeiro WithLabels(...) (Collector.cs):
# fcg_payments_processados_total so passa a existir no /metrics do payments-api DEPOIS que o consumidor
# processa o primeiro OrderPlacedEvent. Lida ANTES da compra -- que era o caso -- ela reprovava a
# gravacao num cluster em que o payments-api subiu ha pouco e ainda nao processou pagamento nenhum:
# falso positivo medido pela revisao. Depois de uma compra ACEITA (202) o evento foi publicado, entao o
# contador TEM de aparecer -- e a espera curta cobre a latencia do consumo assincrono (sem ela, a
# checagem trocaria um falso positivo por uma corrida). Nao ha rebuild do payments-api nesta onda: a
# pre-criacao dos labels ficou parkada como divida.
$mPayments = Metricas 'payments-api:80'
$temContadorPagamentos = [bool]($mPayments -match '(?m)^fcg_payments_processados_total')
if ((-not $temContadorPagamentos) -and $compraAceita) {
    for ($tentativaMetrica = 1; $tentativaMetrica -le 6; $tentativaMetrica++) {
        'aguardando o payments-api consumir o evento da compra aceita (tentativa ' + $tentativaMetrica + '/6)...'
        Start-Sleep -Seconds 5
        $mPayments = Metricas 'payments-api:80'
        if ($mPayments -match '(?m)^fcg_payments_processados_total') { $temContadorPagamentos = $true; break }
    }
}
'contador fcg_payments_processados_total no /metrics do payments-api = ' + $temContadorPagamentos
if ($temContadorPagamentos) {
    Chk $temContadorPagamentos 'metrics-payments-api-contador-de-negocio'
} elseif ($compraAceita) {
    Write-Output 'FALHOU: a compra foi ACEITA (202) e publicou o OrderPlacedEvent, mas o contador'
    Write-Output 'FALHOU: fcg_payments_processados_total nao apareceu no /metrics do payments-api nem'
    Write-Output 'FALHOU: depois de 30s de espera: o painel "Pagamentos processados por status" ficaria'
    Write-Output 'FALHOU: sem serie no bloco 4 (consumidor parado ou instrumentacao ausente).'
    Chk $false 'metrics-payments-api-contador-de-negocio'
} else {
    Write-Output 'ATENCAO: o contador nao esta no /metrics e a compra de verificacao NAO foi aceita nesta'
    Write-Output ('ATENCAO: rodada (codigo ' + $(if ($codCompra) { $codCompra } else { 'nenhum: sem userId/jogo' }) + '): sem evento NOVO consumido,')
    Write-Output 'ATENCAO: a familia com labels pode simplesmente ainda nao existir nesse payments-api (ela'
    Write-Output 'ATENCAO: so nasce no primeiro WithLabels). Para provar o contador, rode de novo.'
    Write-Output '(esta situacao NAO entra na contagem de checagens: nao houve evento para provar o contador)'
}
if ($jogoDemo) {
    # O PUT e upsert por (gameId, userId): 201 na primeira avaliacao e 200 ao atualizar. E o MESMO
    # jogo do bloco 4 (o escolhido no P9), para o roteiro ter um id so.
    $bAval = Body 'avaliacao.json' '{"nota":5,"comentario":"Otimo jogo","tags":["acao"]}'
    $rAval = Resposta ($Gateway + '/api/jogos/' + $jogoDemo + '/avaliacoes') 'PUT' $bAval $token
    'PUT /api/jogos/{id}/avaliacoes = ' + $rAval.Code + '  (esperado 201 na primeira, 200 na atualizacao)'
    Chk (@('200', '201') -contains $rAval.Code) 'avaliacao-upsert-200-ou-201'
    $rListaAval = Resposta ($Gateway + '/api/jogos/' + $jogoDemo + '/avaliacoes') 'GET' $null $token
    'GET /api/jogos/{id}/avaliacoes = ' + $rListaAval.Code + '  (esperado 200: a lista vem do Mongo)'
    Chk ($rListaAval.Code -eq '200') 'avaliacao-listagem-200'
    # Depois deste preflight a avaliacao do usuario de demonstracao JA existe: no video o PUT do
    # bloco 5 devolve 200 (atualizacao), nao 201 -- e isso tambem e a prova do upsert.
} else {
    'sem jogo escolhido: a avaliacao do bloco 5 do video nao pode ser exercitada'
    Chk $false 'avaliacao-upsert-200-ou-201'
    Chk $false 'avaliacao-listagem-200'
}

Step 'P11 - estado inicial da gravacao: funcao em 0 replicas'
if ($token) {
    # Se o usuario de demonstracao foi criado agora (P3) ou a compra do P10b foi aceita, a funcao
    # subiu: espera o cooldown do KEDA para a gravacao comecar com ela em 0 replicas.
    $t0 = Get-Date
    $zero = $false
    while (((Get-Date) - $t0).TotalSeconds -lt $EsperaCooldown) {
        $podsFn = @(Pods 'app=notifications-function')
        $repFn = ((kubectl get -n $namespace deployment notifications-function -o jsonpath='{.spec.replicas}' 2>&1) | Out-String).Trim()
        if (($podsFn.Count -eq 0) -and ($repFn -eq '0')) { $zero = $true; break }
        '  aguardando o cooldown do KEDA (30s) + o termino do pod... pods=' + $podsFn.Count + ' replicas=' + $repFn
        Start-Sleep -Seconds 10
    }
    $podsFn = @(Pods 'app=notifications-function')
    $repFn = ((kubectl get -n $namespace deployment notifications-function -o jsonpath='{.spec.replicas}' 2>&1) | Out-String).Trim()
    'deployment notifications-function: replicas=' + $repFn + '  pods=' + $podsFn.Count + '  (esperado 0 e 0)'
    'kubectl get pods -l app=notifications-function = ' + $(if ($podsFn.Count -eq 0) { 'No resources found' } else { ($podsFn -join ' | ') })
    Chk $zero 'funcao-em-zero-replicas-estado-inicial'
} else {
    'sem token: nao ha como garantir que a funcao foi acordada'
    Chk $false 'funcao-em-zero-replicas-estado-inicial'
}

} catch {
    Write-Output ''
    Write-Output ('ERRO NAO TRATADO: ' + (San $_.Exception.Message))
    Write-Output (San $_.ScriptStackTrace)
    $script:falhas++
} finally {

Step 'RESULTADO'
'checagens=' + $script:checagens + '  falhas=' + $script:falhas
if ($script:falhas -gt 0) {
    Write-Output ('PREFLIGHT REPROVADO: ' + $script:falhas + ' checagem(ns) falhou(aram) -- leia as linhas [FALHOU] acima.')
    Write-Output 'NAO GRAVE ainda: qualquer falha aqui aparece no video como um bloco sem evidencia.'
} else {
    Write-Output 'TUDO PRONTO PARA GRAVAR'
    Write-Output ('  usuario de demonstracao: ' + $Email + ' (senha em FCG_DEMO_SENHA; o bloco do Gateway faz login com ele)')
    Write-Output ('  jogos no catalogo: ' + $jogos.Count)
    Write-Output ('  jogo do bloco 4 (compra) = ' + $jogoDemoNome + ' (' + $jogoDemo + ')  -- e o mesmo id serve para o bloco 5 (avaliacoes)')
    Write-Output '  (este jogo e o primeiro do catalogo que o usuario demo NAO possui: a primeira compra dele devolve 202 e move o painel)'
    Write-Output '  (a compra de verificacao deste preflight foi em OUTRO jogo, de proposito, para nao consumir o do bloco 4)'
    Write-Output '  funcao de notificacoes: 0 replicas (o cadastro do bloco serverless sobe o pod em ~15-30s (pollingInterval de 15s; medido 20-31s))'
    Write-Output '  roteiro: docs/roteiro-video-fase3.md'
}
# O temporario guarda o corpo do login/cadastro com a senha da demo em claro: apagar SEMPRE.
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
'ambiente temporario removido'
}

exit $(if ($script:falhas -gt 0) { 1 } else { 0 })
