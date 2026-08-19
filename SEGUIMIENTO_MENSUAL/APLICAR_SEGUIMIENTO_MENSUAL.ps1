$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "Aplicando seguimiento mensual de facturas EPEN..." -ForegroundColor Green

$repository = Split-Path $PSScriptRoot -Parent
$backend = $null

if (Test-Path (Join-Path $repository "back\app\main.py")) {
    $backend = Join-Path $repository "back"
} elseif (Test-Path (Join-Path $repository "app\main.py")) {
    $backend = $repository
} elseif (Test-Path (Join-Path (Get-Location) "back\app\main.py")) {
    $backend = Join-Path (Get-Location) "back"
}

if (-not $backend) {
    Write-Host "No encontre el backend." -ForegroundColor Red
    Write-Host "Extrae este ZIP dentro de la raiz Ahorro-energetico y vuelve a ejecutarlo."
    Read-Host "Presiona ENTER para cerrar"; exit 1
}

$backup = Join-Path $backend ("backup_seguimiento_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path (Join-Path $backup "app\routers") | Out-Null
Copy-Item (Join-Path $backend "app\importer.py") (Join-Path $backup "app\importer.py") -Force
Copy-Item (Join-Path $backend "app\routers\imports.py") (Join-Path $backup "app\routers\imports.py") -Force

Copy-Item ".\payload\app\importer.py" (Join-Path $backend "app\importer.py") -Force
Copy-Item ".\payload\app\routers\imports.py" (Join-Path $backend "app\routers\imports.py") -Force
Copy-Item ".\payload\README.md" (Join-Path $backend "README.md") -Force

Write-Host "Cambio aplicado correctamente." -ForegroundColor Green
Write-Host "Cada medidor conservara un ID EPEN-000001 y se avisaran faltantes mensuales."
Write-Host "Sube los cambios a GitHub para que Render vuelva a desplegar el backend." -ForegroundColor Cyan
Write-Host "Backup creado en: $backup" -ForegroundColor Yellow
Read-Host "Presiona ENTER para cerrar"
