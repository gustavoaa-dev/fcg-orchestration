# Gerador de trafego autenticado para a gravacao do video da Fase 3 (FCG) -- ASCII puro, sem BOM.
# Roda em Windows PowerShell 5.1. EXIT=1 se o setup falhar (senha ausente, login recusado, catalogo
# vazio) ou se NENHUMA requisicao tiver sido aceita.
#
# O que ele faz:
#   1. SENHA DA DEMONSTRACAO: vem de $env:FCG_DEMO_SENHA (ou do parametro -Senha). NAO ha senha
#      default neste arquivo -- sem ela o script aborta com mensagem clara;
#   2. login em POST /api/auth/login (rota publica do gateway) e captura do token NA MESMA sessao;
#   3. enquanto o cronometro nao zera, alterna entre GET /api/jogos, GET /api/jogos/{id} e
#      GET /api/jogos/{id}/avaliacoes, com pausa de 200 ms entre chamadas, imprimindo o contador
#      de requisicoes a cada 5 segundos;
#   4. no fim, imprime o total por endpoint e por status code.
#
# Para que serve: com o dashboard FCG - APIs aberto, as series de RPS e de latencia (p50/p95) se
# movem em ate 15 s -- que e o intervalo de scrape do Prometheus (k8s/prometheus-configmap.yaml).
# O trafego passa pelo gateway, entao users-api e catalog-api aparecem no painel de status code
# (o Kong nao e instrumentado nesta fase).
#
# SEGREDOS: a senha nunca e impressa nem gravada em arquivo; o token tambem nao (so o tamanho).
#
# Uso: $env:FCG_DEMO_SENHA = '<senha>'; powershell -ExecutionPolicy Bypass -File scripts/demo-trafego.ps1 -Segundos 90
param(
    [int]$Segundos = 60,
    [string]$Gateway = 'http://localhost:8000',
    [string]$Email = 'demo@fcg.local',
    # SEM default: a senha da demonstracao NAO pode ficar versionada (regra global de segredos).
    [string]$Senha = $env:FCG_DEMO_SENHA,
    [int]$PausaMs = 200
)

$script:falhas = 0
$script:checagens = 0

function Chk($cond, $rotulo) {
    $script:checagens++
    $ok = [bool]$cond
    if (-not $ok) { $script:falhas++ }
    Write-Output ($rotulo + '=' + $ok + '  [' + $(if ($ok) { 'OK' } else { 'FALHOU' }) + ']')
}
# Tira qualquer segredo de um texto antes de imprimir (defesa em profundidade: nada aqui deveria
# carregar a senha, mas a saida nunca e impressa sem passar por aqui).
function San($texto) {
    $s = [string]$texto
    if ($Senha -and $Senha.Length -ge 4) { $s = $s.Replace($Senha, '***') }
    return $s
}
# O corpo do login vai por ARQUIVO (-d '@arquivo'): JSON inline perde as aspas no PowerShell.
# O diretorio nasce na primeira chamada e e SEMPRE removido no fim: o arquivo tem a senha em claro.
$script:tmpDir = $null
function Body($json) {
    if (-not $script:tmpDir) {
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('fcg-trafego-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
    }
    $p = Join-Path $script:tmpDir ('corpo-' + [guid]::NewGuid().ToString('N') + '.json')
    Set-Content -Path $p -Value $json -Encoding Ascii -NoNewline
    return '@' + $p
}
function Limpar {
    if ($script:tmpDir -and (Test-Path $script:tmpDir)) { Remove-Item $script:tmpDir -Recurse -Force }
}
# Devolve o corpo + o status da MESMA chamada (a separacao usa '|').
function Resposta($url, $method, $bodyArg, $token) {
    $a = @('-s', '--max-time', '30', '-X', $method)
    if ($bodyArg) { $a += @('-H', 'Content-Type: application/json', '-d', $bodyArg) }
    if ($token) { $a += @('-H', ('Authorization: Bearer ' + $token)) }
    $a += @('-w', '|%{http_code}', $url)
    $raw = San ([string](& curl.exe @a))
    $i = $raw.LastIndexOf('|')
    if ($i -lt 0) { return @{ Code = ''; Body = $null } }
    $code = $raw.Substring($i + 1).Trim()
    $obj = $null
    try { $obj = ($raw.Substring(0, $i) | ConvertFrom-Json) } catch { }
    return @{ Code = $code; Body = $obj }
}
# Requisicao de trafego: so o status interessa (o corpo e descartado no proprio curl).
function Codigo($url, $token) {
    return (San ([string](& curl.exe -s -o NUL -w '%{http_code}' --max-time 30 -H ('Authorization: Bearer ' + $token) $url))).Trim()
}

Write-Output ('gerador de trafego da Fase 3 -- gateway=' + $Gateway + ' usuario=' + $Email + ' segundos=' + $Segundos)
Write-Output ''

# 1) Senha da demonstracao
if (-not $Senha) {
    Write-Output 'FALHOU: a senha da demonstracao nao foi informada.'
    Write-Output 'NAO existe senha default neste arquivo (regra global de segredos). Use:'
    Write-Output '  $env:FCG_DEMO_SENHA = ''<senha-da-demonstracao>'''
    Write-Output '  powershell -ExecutionPolicy Bypass -File scripts/demo-trafego.ps1 -Segundos 90'
    Write-Output 'O usuario de demonstracao (e a senha) sao criados/validados pelo preflight:'
    Write-Output '  powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1'
    exit 1
}

# 2) Login: sem token nao ha trafego autenticado (o Kong responde 401 antes de chegar a API).
$rLogin = Resposta ($Gateway + '/api/auth/login') 'POST' (Body ('{"email":"' + $Email + '","senha":"' + $Senha + '"}')) $null
Chk ($rLogin.Code -eq '200') 'login-200'
$token = $null
if ($rLogin.Body) { $token = $rLogin.Body.token }
Chk ([bool]$token) 'token-recebido'
if ($token) { 'token obtido: ' + $token.Length + ' caracteres (valor nunca e impresso)' }

# 3) Catalogo: sem jogo nao ha o que requisitar (e o dashboard nao veria trafego de negocio).
$ids = @()
if ($token) {
    $rLista = Resposta ($Gateway + '/api/jogos') 'GET' $null $token
    Chk ($rLista.Code -eq '200') 'catalogo-200'
    # O Where-Object nao e enfeite: @($null) conta como UM elemento no PowerShell.
    foreach ($j in @($rLista.Body | Where-Object { $_ -ne $null })) { if ($j.id) { $ids += $j.id } }
    'jogos no catalogo = ' + $ids.Count
}
Chk ($ids.Count -ge 1) 'catalogo-com-pelo-menos-um-jogo'

if ($script:falhas -gt 0) {
    Write-Output ''
    Write-Output ('SETUP REPROVADO: ' + $script:falhas + ' checagem(ns) falhou(aram) -- nenhum trafego foi gerado.')
    Write-Output 'Rode o preflight (scripts/preflight-fase3.ps1) e corrija o que ele apontar antes de gravar.'
    Limpar
    exit 1
}

# 4) Laco de trafego: alterna os tres endpoints de leitura do catalog-api.
$jogoId = $ids[0]
$rotas = @(
    ($Gateway + '/api/jogos'),
    ($Gateway + '/api/jogos/' + $jogoId),
    ($Gateway + '/api/jogos/' + $jogoId + '/avaliacoes')
)
$contagem = @{}
foreach ($r in $rotas) { $contagem[$r] = 0 }
$status = @{}
$total = 0
$ok = 0
$crono = [System.Diagnostics.Stopwatch]::StartNew()
$ultimoAviso = 0
try {
    while ($crono.Elapsed.TotalSeconds -lt $Segundos) {
        foreach ($rota in $rotas) {
            $code = Codigo $rota $token
            $total++
            if ($code -eq '200' -or $code -eq '201') { $ok++ }
            if ($contagem.ContainsKey($rota)) { $contagem[$rota] = $contagem[$rota] + 1 }
            if (-not $status.ContainsKey($code)) { $status[$code] = 0 }
            $status[$code] = $status[$code] + 1
            Start-Sleep -Milliseconds $PausaMs
            if ($crono.Elapsed.TotalSeconds -ge $Segundos) { break }
        }
        $decorrido = [int]$crono.Elapsed.TotalSeconds
        if (($decorrido - $ultimoAviso) -ge 5) {
            $ultimoAviso = $decorrido
            Write-Output ('  ' + $decorrido + 's/' + $Segundos + 's  requisicoes=' + $total + '  ok=' + $ok)
        }
    }
} finally {
    $crono.Stop()
    Write-Output ''
    Write-Output 'resumo do trafego'
    Write-Output ('  duracao = ' + [int]$crono.Elapsed.TotalSeconds + 's  requisicoes = ' + $total + '  aceitas(200) = ' + $ok)
    foreach ($r in $rotas) { Write-Output ('  ' + $r + ' -> ' + $contagem[$r]) }
    Write-Output ('  status codes = ' + (($status.Keys | Sort-Object | ForEach-Object { $_ + ':' + $status[$_] }) -join '  '))
    Limpar
    'ambiente temporario removido'
}

# Trafego nenhum nao move painel algum: isso e falha, nao sucesso silencioso.
Chk ($total -gt 0) 'trafego-gerado'
Chk ($ok -gt 0) 'requisicoes-aceitas'
if ($script:falhas -gt 0) {
    Write-Output ''
    Write-Output ('TRAFEGO REPROVADO: ' + $script:falhas + ' checagem(ns) falhou(aram).')
} else {
    Write-Output ''
    Write-Output 'TRAFEGO OK: com o dashboard FCG - APIs aberto, as series de RPS e latencia sobem em ate 15s'
    Write-Output '(intervalo de scrape do Prometheus). Os paineis excluem as probes /health: o que aparece e'
    Write-Output 'trafego de negocio -- as chamadas reais feitas por este script pelo gateway.'
}

exit $(if ($script:falhas -gt 0) { 1 } else { 0 })
