$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if (Test-Path (Join-Path $Root "back\app\routers\tariff_history.py")) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if (Test-Path (Join-Path $Parent "back\app\routers\tariff_history.py")) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$target=Join-Path $Repo "back\app\routers\tariff_history.py"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup="$target.bak-v12-$stamp"
Copy-Item $target $backup -Force

Copy-Item (Join-Path $Root "payload\back\app\routers\tariff_history.py") $target -Force

Write-Host ""
Write-Host "OK - V12 aplicada." -ForegroundColor Green
Write-Host "El cálculo ahora es:" -ForegroundColor Yellow
Write-Host "  T3/T3A REAL de invoice_lines - T4 SIMULADA"
Write-Host ""
Write-Host "No se simula más el costo actual T3/T3A."
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "IMPORTANTE: desplegá el backend en Render."
