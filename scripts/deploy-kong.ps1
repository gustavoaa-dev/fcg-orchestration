# Renderiza k8s/kong/kong.yml a partir do template, substituindo ${JWT_SECRET} pelo segredo
# que ja existe no cluster (Secret users-api-secret, chave jwt-secret-key) e recria o
# Secret kong-declarative-config. Nenhum valor de segredo entra no repositorio.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $repoRoot 'k8s/kong/kong.yml.template'

if (-not (Test-Path $templatePath)) {
    throw "Template nao encontrado: $templatePath"
}

$secretBase64 = kubectl get secret users-api-secret -o jsonpath='{.data.jwt-secret-key}'
if (-not $secretBase64) {
    throw "Secret 'users-api-secret' (chave jwt-secret-key) nao encontrado no cluster. Aplique os manifestos das APIs antes de subir o Kong."
}
$jwtSecret = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secretBase64))

$rendered = (Get-Content -Path $templatePath -Raw).Replace('${JWT_SECRET}', $jwtSecret)
# GetTempPath() em vez de $env:TEMP: $env:TEMP pode ser nulo em contexto de servico.
$renderedPath = Join-Path ([System.IO.Path]::GetTempPath()) 'kong-rendered.yml'

try {
    # UTF8Encoding($false) = UTF-8 sem BOM, independente da versao do PowerShell.
    # Com BOM, o kong.yml montado no container pode falhar no parse da config declarativa.
    [System.IO.File]::WriteAllText($renderedPath, $rendered, (New-Object System.Text.UTF8Encoding($false)))

    kubectl create secret generic kong-declarative-config `
        --from-file=kong.yml=$renderedPath `
        --dry-run=client -o yaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw "kubectl falhou (exit $LASTEXITCODE)" }

    kubectl rollout restart deployment/kong
    if ($LASTEXITCODE -ne 0) { throw "kubectl falhou (exit $LASTEXITCODE)" }
}
finally {
    # O temporario contem o segredo em claro: remover sempre, inclusive se o kubectl falhar.
    if (Test-Path $renderedPath) { Remove-Item $renderedPath -Force }
}

Write-Host "Secret kong-declarative-config atualizado e Kong reiniciado (kubectl exit 0 em ambos os passos)."
