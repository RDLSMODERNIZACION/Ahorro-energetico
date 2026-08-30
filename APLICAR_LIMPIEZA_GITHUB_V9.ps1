$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if ((Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Root "back\app\main.py"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Parent "back\app\main.py"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

Write-Host "Repositorio: $Repo" -ForegroundColor Cyan
python (Join-Path $Root "APLICAR_LIMPIEZA_GITHUB_V9.py") $Repo
if($LASTEXITCODE -ne 0){throw "Falló la limpieza V9."}

Write-Host ""
Write-Host "OK - Limpieza basada en el GitHub actual aplicada." -ForegroundColor Green
Write-Host "Ahora ejecutá:" -ForegroundColor Yellow
Write-Host "  cd front"
Write-Host "  npm run dev"
