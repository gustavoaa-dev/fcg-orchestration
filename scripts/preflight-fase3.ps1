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
#   P9  DADOS DE DEMONSTRACAO: pelo menos 2 jogos no catalogo; se faltar, promove o usuario de
#       demonstracao a Admin direto no SQL Server (a senha NAO vai na linha de comando: o sh -c usa
#       o $SA_PASSWORD que o pod ja tem no ambiente), refaz o login e cria os jogos que faltam
#   P10 Redis com as chaves catalog:* e o Mongo respondendo (GET .../avaliacoes = 200)
#   P10b os comandos que SO aparecem no video sao exercitados aqui: as series dos paineis em
#       /metrics (proxy do kubectl, sem port-forward), a compra (so 202 e [OK]: e a compra ACEITA
#       que move o painel de pagamentos) e o PUT/GET de avaliacao (upsert: 201 na 1a, 200 na 2a)
#   P11 FUNCAO EM 0 REPLICAS (estado inicial da demo), esperando o cooldown do KEDA se preciso
#
# CONTAGEM: "checagens" conta apenas PEDACOS QUE FORAM DE FATO VERIFICADOS. Os dois casos de ATENCAO
# (log da funcao ainda ausente no Loki e compra recusada por posse) NAO emitem [OK] e NAO incrementam
# o contador -- por isso o total varia de 47 a 51 conforme o que o cluster devolve (ver o relatorio).
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
    [int]$JogosMinimos = 2,
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

Step 'P9 - dados de demonstracao: jogos no catalogo'
$lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
$jogos = @($lista.Body | Where-Object { $_ -ne $null })
'GET /api/jogos = ' + $lista.Code + '  jogos no catalogo = ' + $jogos.Count + '  (minimo ' + $JogosMinimos + ')'
Chk ($lista.Code -eq '200') 'catalogo-listagem-200'
if ($jogos.Count -lt $JogosMinimos) {
    Write-Output '*** AVISO: faltam jogos para a demonstracao (o dado do SQL Server e volatil enquanto o ***'
    Write-Output '*** AVISO: PVC nao entrar: qualquer restart de container esvazia o banco). Criando agora. ***'
    # O POST /api/jogos exige Admin e a users-api registra todos como Usuario: promocao direta no SQL.
    # A senha do sa NAO vai na linha de comando: o pod do sqlserver ja tem SA_PASSWORD no ambiente
    # (secretKeyRef do sqlserver-secret, em k8s/sqlserver-deployment.yaml) e o sh -c a expande DENTRO
    # do container. Assim ela nao aparece em "kubectl ... -P <senha>" (argv visivel em ps/audit log).
    $sa = SecretValor 'sqlserver-secret' 'sa-password'
    # O Secret ainda e lido em memoria: se ele nao existir, o container tambem esta sem SA_PASSWORD e o
    # sqlcmd falharia de um jeito confuso -- melhor reprovar aqui, com a causa.
    Chk ([bool]$sa) 'secret-sqlserver-sa-password-presente'
    if (-not $sa) {
        'NAO consegui ler o Secret sqlserver-secret/sa-password: o POST de jogo vai responder 403.'
    } else {
        $script:segredos += $sa
        $sql = "UPDATE FCG_Users.dbo.Users SET Role = 1 WHERE Email = '" + $Email + "'"
        $cmdSql = '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "' + $sql + '"'
        $saidaSql = (San (((kubectl exec -n $namespace deploy/sqlserver -- sh -c $cmdSql 2>&1) | ForEach-Object { [string]$_ }) -join "`n")).Trim()
        'promocao do usuario de demonstracao a Admin (sqlcmd dentro do pod, com $SA_PASSWORD do ambiente):'
        $(if ($saidaSql) { '  ' + $saidaSql } else { '  (sem saida)' })
        $token = Token
        Chk ([bool]$token) 'login-apos-promocao-a-Admin'
    }
    for ($i = $jogos.Count; $i -lt $JogosMinimos; $i++) {
        $bJogo = Body ('jogo-' + ($i + 1) + '.json') ('{"nome":"Jogo Demo ' + ($i + 1) + '","descricao":"Jogo de demonstracao da Fase 3","preco":' + (49 + $i) + '.90}')
        $rJogo = Resposta ($Gateway + '/api/jogos') 'POST' $bJogo $token
        'POST /api/jogos = ' + $rJogo.Code + '  (esperado 201)  nome=Jogo Demo ' + ($i + 1)
        if ($rJogo.Code -ne '201') { break }
    }
    $lista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
    $jogos = @($lista.Body | Where-Object { $_ -ne $null })
    'jogos no catalogo apos a criacao = ' + $jogos.Count
}
Chk ($jogos.Count -ge $JogosMinimos) 'catalogo-com-jogos-para-a-demo'
$jogoId = $null
if ($jogos.Count -ge 1) { $jogoId = $jogos[0].id }
'primeiro jogo (usado nos blocos NoSQL/compra do video) = ' + $jogoId

Step 'P10 - Redis (cache) e MongoDB (avaliacoes)'
# O TTL da chave e de 60s: a listagem e lida IMEDIATAMENTE antes de olhar o Redis.
$sLista = Status ($Gateway + '/api/jogos') 'GET' $null $token
$chaves = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli keys 'catalog:*' 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
'GET /api/jogos (aquece o cache) = ' + $sLista
'redis-cli keys catalog:* = ' + $(if ($chaves) { $chaves } else { '(vazio)' })
Chk ($chaves -match 'catalog:') 'redis-com-chaves-catalog'
if ($jogoId) {
    $tipo = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli type catalog:games:all 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
    $ttl = (San (((kubectl exec -n $namespace deploy/redis -- redis-cli ttl catalog:games:all 2>&1) | ForEach-Object { [string]$_ }) -join ' ')).Trim()
    'redis-cli type/ttl catalog:games:all = ' + $tipo + ' / ' + $ttl + '  (esperado hash / ate 60)'
    $mongo = Resposta ($Gateway + '/api/jogos/' + $jogoId + '/avaliacoes') 'GET' $null $token
    'GET /api/jogos/{id}/avaliacoes = ' + $mongo.Code + '  (esperado 200: e o caminho do Mongo)'
    Chk ($mongo.Code -eq '200') 'mongo-avaliacoes-200'
} else {
    'sem jogo no catalogo: a checagem do Mongo nao pode rodar'
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
$userId = Claim $token 'Id'
'userId (claim Id do token, usado na compra) = ' + $userId
# A compra do preflight usa o ULTIMO jogo do catalogo DE PROPOSITO: o video compra o PRIMEIRO (bloco
# 4), e e a PRIMEIRA compra daquele par (usuario, jogo) que devolve 202 e move o painel de
# pagamentos. Comprando o primeiro aqui, o video poderia receber 400/409 ("ja possui este jogo").
$jogoCompra = $jogoId
if ($jogos.Count -ge 2) { $jogoCompra = $jogos[$jogos.Count - 1].id }
if ($userId -and $jogoCompra) {
    $bCompra = Body 'compra.json' ('{"userId":"' + $userId + '","gameId":"' + $jogoCompra + '"}')
    $rCompra = Resposta ($Gateway + '/api/jogos/' + $jogoCompra + '/comprar') 'POST' $bCompra $token
    'POST /api/jogos/{id}/comprar = ' + $rCompra.Code + '  (esperado 202)  jogo=' + $jogoCompra
    '  corpo = ' + $rCompra.Texto
    # SO 202 e [OK]: e a compra ACEITA que publica OrderPlacedEvent e move o painel "Pagamentos
    # processados por status" do bloco 4. 400/409 costumam ser "o usuario de demonstracao ja possui
    # este jogo" (rodada anterior do preflight): nao impede gravar, mas entao NAO houve verificacao da
    # compra -- sai ATENCAO e a checagem NAO e contada (nada de [OK] sem verificacao).
    $compraAceita = ($rCompra.Code -eq '202')
    if ($compraAceita) {
        Chk $compraAceita 'compra-aceita-202'
    } else {
        Write-Output ('ATENCAO: a compra devolveu ' + $rCompra.Code + ' em vez de 202 -- o painel de pagamentos')
        Write-Output 'ATENCAO: so se move com uma compra ACEITA. Se o corpo acima falar de posse/jogo, crie'
        Write-Output 'ATENCAO: um jogo novo antes de gravar o bloco 4.'
        Write-Output '(esta situacao NAO entra na contagem de checagens: a compra nao foi aceita)'
    }
} else {
    'sem userId no token ou sem jogo: a compra do bloco 4 do video nao pode ser exercitada'
    Chk $false 'compra-aceita-202'
}
if ($jogoId) {
    # O PUT e upsert por (gameId, userId): 201 na primeira avaliacao e 200 ao atualizar.
    $bAval = Body 'avaliacao.json' '{"nota":5,"comentario":"Otimo jogo","tags":["acao"]}'
    $rAval = Resposta ($Gateway + '/api/jogos/' + $jogoId + '/avaliacoes') 'PUT' $bAval $token
    'PUT /api/jogos/{id}/avaliacoes = ' + $rAval.Code + '  (esperado 201 na primeira, 200 na atualizacao)'
    Chk (@('200', '201') -contains $rAval.Code) 'avaliacao-upsert-200-ou-201'
    $rListaAval = Resposta ($Gateway + '/api/jogos/' + $jogoId + '/avaliacoes') 'GET' $null $token
    'GET /api/jogos/{id}/avaliacoes = ' + $rListaAval.Code + '  (esperado 200: a lista vem do Mongo)'
    Chk ($rListaAval.Code -eq '200') 'avaliacao-listagem-200'
    # Depois deste preflight a avaliacao do usuario de demonstracao JA existe: no video o PUT do
    # bloco 5 devolve 200 (atualizacao), nao 201 -- e isso tambem e a prova do upsert.
} else {
    'sem jogo no catalogo: a avaliacao do bloco 5 do video nao pode ser exercitada'
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
    Write-Output ('  jogos no catalogo: ' + $jogos.Count + ' -- o bloco NoSQL e o de pagamentos do video usam o PRIMEIRO id')
    Write-Output '  (a compra deste preflight foi no ULTIMO jogo de proposito: a primeira compra daquele par usuario+jogo e a que devolve 202)'
    Write-Output '  funcao de notificacoes: 0 replicas (o cadastro do bloco serverless sobe o pod em ~15-30s)'
    Write-Output '  roteiro: docs/roteiro-video-fase3.md'
}
# O temporario guarda o corpo do login/cadastro com a senha da demo em claro: apagar SEMPRE.
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
'ambiente temporario removido'
}

exit $(if ($script:falhas -gt 0) { 1 } else { 0 })
