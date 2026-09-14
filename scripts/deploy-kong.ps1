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
$renderedPath = Join-Path $env:TEMP 'kong-rendered.yml'
Set-Content -Path $renderedPath -Value $rendered -Encoding UTF8 -NoNewline

kubectl create secret generic kong-declarative-config `
    --from-file=kong.yml=$renderedPath `
    --dry-run=client -o yaml | kubectl apply -f -

Remove-Item $renderedPath -Force

kubectl rollout restart deployment/kong
Write-Host "Secret kong-declarative-config atualizado e Kong reiniciado."
