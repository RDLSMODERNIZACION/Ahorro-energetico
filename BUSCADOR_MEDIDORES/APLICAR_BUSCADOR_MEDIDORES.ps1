$ErrorActionPreference = "Stop"
$package = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $package
$front = Join-Path $root "front"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path (Join-Path $front "app\page.tsx"))) {
    Write-Host "No encontre el frontend en: $front" -ForegroundColor Red
    Write-Host "Extrae este ZIP dentro de C:\Users\administrador\Documents\Ahorro-energetico" -ForegroundColor Yellow
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}

Write-Host "Agregando buscador de medidores y suministros..." -ForegroundColor Cyan
$targets = @("analysis-charts.tsx", "globals.css")
foreach ($name in $targets) {
    $source = Join-Path $package "payload\$name"
    $target = Join-Path $front "app\$name"
    if (Test-Path $target) { Copy-Item $target "$target.bak-$stamp" -Force }
    Copy-Item $source $target -Force
    Write-Host "Actualizado: $target" -ForegroundColor Green
}

Write-Host "" 
Write-Host "Listo. Busca por medidor, suministro o nombre del servicio." -ForegroundColor Green
Read-Host "Presiona ENTER para cerrar"
