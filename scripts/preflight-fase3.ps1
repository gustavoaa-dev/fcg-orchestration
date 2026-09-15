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
#       (o rotulo so nasce depois que a funcao sobe uma vez na retencao de 24h) e Chk de verdade
#       quando existe: em nenhum dos casos ha [OK] sem verificacao -- ver a nota de contagem abaixo.
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
#       catalogo E nao esta na biblioteca lida)
#   P10 Redis com as chaves catalog:* e o Mongo respondendo (GET .../avaliacoes = 200)
#   P10b os comandos que SO aparecem no video sao exercitados aqui: as series dos paineis em
#       /metrics (proxy do kubectl, sem port-forward), a compra de verificacao -- que usa OUTRO jogo,
#       para nao consumir o do bloco 4, e so 202 e [OK]: 400/409 sao re-execucao (ATENCAO, nao conta) e
#       QUALQUER outro codigo (401/403/5xx/000) REPROVA -- e o PUT/GET de avaliacao (upsert: 201 na 1a,
#       200 na 2a) no jogo do bloco 4
#   P11 FUNCAO EM 0 REPLICAS (estado inicial da demo), esperando o cooldown do KEDA se preciso
#
# CONTAGEM: "checagens" conta apenas PEDACOS QUE FORAM DE FATO VERIFICADOS. Os casos de ATENCAO
# (log da funcao ainda ausente no Loki; compra devolvendo 400/409 por posse; biblioteca devolvendo 404
# por ainda nao existir -- que tambem tira a checagem do jogo do bloco 4, porque sem a lista lida a
# posse nao pode ser verificada) sao VARIACAO LEGITIMA DE ESTADO: NAO emitem [OK] e NAO incrementam o
# contador. Todo o resto reprova -- generalizar "!= 202" ou "!= 200" para ATENCAO engoliria justamente
# os codigos que denunciam um endpoint quebrado. O total varia de 47 a 54: 51 no caminho ideal, +3 se o
# preflight precisar promover o usuario a Admin (secret, login e o Role lido do banco), e -1 por cada
# ATENCAO (-2 quando a biblioteca nao e lida: a checagem dela e a do jogo do bloco 4).
#
# Nada de port-forward: o Prometheus e o Loki sao alcancados pelo proxy do kubectl
# (kubectl get --raw .../services/<svc>:<porta>/proxy/...) e o Grafana por kubectl exec + wget.
# Namespace: o proxy exige o namespace no caminho, entao os exec/get usam -n $namespace com o mesmo
# valor ($namespace = 'default') -- as duas metades olham para o mesmo lugar, sempre.
#
# SEGREDOS: a senha da demonstracao vem de $env:FCG_DEMO_SENHA (nao ha senha default no arquivo) e
# os valores de Secret do cluster sao decodificados em memoria. O unico lugar em que uma senha toca
# o disco e o corpo JSON temporario do login/cadastro, apagado no fim (bloco finally); toda saida
# passa por San(), que troca os segredos por *** antes de imprimir -- inclusive a forma ESCAPADA da
# senha do Grafana (a URL do kubectl exec carrega a senha URL-encoded, nao o valor cru).
#
# Uso: $env:FCG_DEMO_SENHA = '<senha>'; powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1
param(
    [string]$Gateway = 'http://localhost:8000',
    [string]$Email = 'demo@fcg.local',
    [string]$Nome = 'Jogador Demo',
    # SEM default: a senha da demonstracao NAO pode ficar versionada (regra global de segredos).
    [string]$Senha = $env:FCG_DEMO_SENHA,
    [int]$JogosMinimos = 3,
    [int]$EsperaCooldown = 180
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
function Partir($raw) {
    $i = $raw.LastIndexOf('|')
    if ($i -lt 0) { return @{ Code = ''; Texto = $raw; Body = $null } }
    $code = $raw.Substring($i + 1).Trim()
    $texto = $raw.Substring(0, $i)
    $obj = $null
    try { $obj = ($texto | ConvertFrom-Json) } catch { }
    return @{ Code = $code; Texto = $texto; Body = $obj }
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
function GrafanaApi($caminho) {
    $url = 'http://admin:' + [uri]::EscapeDataString($script:senhaGrafana) + '@localhost:3000' + $caminho
    return (San (((kubectl exec -n $namespace deploy/grafana -- wget -qO- $url 2>&1) | ForEach-Object { [string]$_ }) -join "`n"))
}
function Token {
    $b = Body 'login.json' ('{"email":"' + $Email + '","senha":"' + $Senha + '"}')
    $r = Resposta ($Gateway + '/api/auth/login') 'POST' $b $null
    # Guarda o status para a evidencia: o corpo do login traz o token e nunca e impresso.
    $script:ultimoLogin = $r.Code
    if ($r.Body) { return $r.Body.token }
    return $null
}

if (-not $Senha) {
    Write-Output 'FALHOU: a senha da demonstracao nao foi informada.'
    Write-Output 'Defina a variavel de ambiente e rode de novo (a senha NUNCA e versionada):'
    Write-Output '  $env:FCG_DEMO_SENHA = ''<senha-da-demonstracao>'''
    Write-Output '  powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1'
    Write-Output 'A senha precisa atender a politica do cadastro: 8+ caracteres, com ao menos uma letra,'
    Write-Output 'um digito e um caractere especial.'
    exit 1
}
$script:segredos += $Senha
# O diretorio temporario so nasce depois da checagem da senha (nada e criado se ela faltar).
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

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
# A checagem do log da FUNCAO e a propria existencia do rotulo -- mas ela NAO pode reprovar a gravacao:
# o rotulo so existe depois de a funcao subir UMA vez dentro da retencao de 24h do Loki, e quem vai
# fazer a funcao subir e o proprio video (o cadastro do bloco 3). Por isso, quando o rotulo existe o
# Chk roda de verdade (1 checagem); quando nao existe, sai ATENCAO e a checagem NAO e contada --
# nada de [OK] sem verificacao.
$temLogDaFuncao = ($rotulos -contains 'notifications-function')
if ($temLogDaFuncao) {
    Chk $temLogDaFuncao 'loki-log-da-funcao-de-notificacoes'
} else {
    Write-Output 'ATENCAO: ainda nao ha log de notifications-function no Loki (a funcao nao rodou nas'
    Write-Output 'ATENCAO: ultimas 24h). Faca um cadastro pelo gateway e confira de novo; o bloco'
    Write-Output 'ATENCAO: serverless do video gera esse log ao vivo e o painel do Grafana mostra ele.'
    Write-Output '(esta situacao NAO entra na contagem de checagens: nao ha o que verificar ainda)'
}

Step 'P7 - Grafana: saude, datasources e dashboards'
$script:senhaGrafana = SecretValor 'grafana-admin' 'admin-password'
if (-not $script:senhaGrafana) {
    'nao consegui ler o Secret grafana-admin/admin-password: a API do Grafana nao sera consultada'
    Chk $false 'grafana-health-ok'
    Chk $false 'grafana-datasource-loki'
    Chk $false 'grafana-dashboard-fcg-apis'
    Chk $false 'grafana-dashboard-fcg-logs'
} else {
    $script:segredos += $script:senhaGrafana
    # A URL do Grafana carrega a senha ESCAPADA ([uri]::EscapeDataString): "P@ss!9#x" vira
    # "P%40ss!9%23x" e nao seria mascarado pelo valor cru. As duas formas entram na lista.
    $script:segredos += [uri]::EscapeDataString($script:senhaGrafana)
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
}

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
Chk ($lista.Code -eq '200') 'catalogo-listagem-200'
if ($jogos.Count -lt $JogosMinimos) {
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
    # A checagem NAO pode dar [OK] so pelo transporte: 200 com itens e ZERO ids reconhecidos e QUEBRA
    # DE CONTRATO (foi assim que a escolha errada saiu com a linha verde na rodada 2). Lista vazia e
    # legitima: o usuario simplesmente nao possui nada.
    $bibliotecaInterpretavel = ($itensBiblioteca.Count -eq 0) -or ($idsBiblioteca.Count -eq $itensBiblioteca.Count)
    'biblioteca do usuario demo = ' + $itensBiblioteca.Count + ' item(ns), ' + $idsBiblioteca.Count + ' id(s) reconhecido(s)'
    if ($bibliotecaInterpretavel) {
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
$mUsers = Metricas 'users-api:80'
$mCatalog = Metricas 'catalog-api:80'
$mPayments = Metricas 'payments-api:80'
Chk ($mUsers -match 'http_requests_received_total') 'metrics-users-api-http-requests'
Chk ($mCatalog -match 'http_requests_received_total') 'metrics-catalog-api-http-requests'
Chk ($mCatalog -match '(?m)^cache_hit') 'metrics-catalog-api-cache-hit'
Chk ($mCatalog -match '(?m)^cache_miss') 'metrics-catalog-api-cache-miss'
Chk ($mPayments -match '(?m)^fcg_payments_processados_total') 'metrics-payments-api-contador-de-negocio'
# A compra do preflight NAO usa o jogo do bloco 4: usa o ULTIMO jogo do catalogo que NAO seja ele.
# Motivo: o jogo escolhido no P9 e o que o video vai comprar, e so a PRIMEIRA compra daquele par
# (usuario, jogo) devolve 202 e move o painel de pagamentos -- consumindo-o aqui, o bloco 4 cairia em
# 400/409. Com o minimo de 3 jogos sempre existe outro candidato.
$jogoVerificacao = $null
for ($i = $jogos.Count - 1; $i -ge 0; $i--) {
    $idCand = [string]$jogos[$i].id
    if ($idCand -and ($idCand -ne $jogoDemo)) { $jogoVerificacao = $idCand; break }
}
if ($userId -and $jogoVerificacao) {
    $bCompra = Body 'compra.json' ('{"userId":"' + $userId + '","gameId":"' + $jogoVerificacao + '"}')
    $rCompra = Resposta ($Gateway + '/api/jogos/' + $jogoVerificacao + '/comprar') 'POST' $bCompra $token
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
    Write-Output '  funcao de notificacoes: 0 replicas (o cadastro do bloco serverless sobe o pod em ~15-30s)'
    Write-Output '  roteiro: docs/roteiro-video-fase3.md'
}
# O temporario guarda o corpo do login/cadastro com a senha da demo em claro: apagar SEMPRE.
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
'ambiente temporario removido'
}

exit $(if ($script:falhas -gt 0) { 1 } else { 0 })
