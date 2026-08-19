$ErrorActionPreference = "Stop"
$package = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $package
$front = Join-Path $root "front"
$back = Join-Path $root "back"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path (Join-Path $front "app\page.tsx"))) {
    Write-Host "No encontre el frontend en: $front" -ForegroundColor Red
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}
if (-not (Test-Path (Join-Path $back "app\routers\catalog.py"))) {
    Write-Host "No encontre el backend en: $back" -ForegroundColor Red
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}

Write-Host "Aplicando seguimiento de medidores sin facturacion..." -ForegroundColor Cyan
$targets = @(
    @{Source="payload\front\page.tsx";Target=(Join-Path $front "app\page.tsx")},
    @{Source="payload\front\globals.css";Target=(Join-Path $front "app\globals.css")},
    @{Source="payload\front\analysis-charts.tsx";Target=(Join-Path $front "app\analysis-charts.tsx")},
    @{Source="payload\back\catalog.py";Target=(Join-Path $back "app\routers\catalog.py")},
    @{Source="payload\back\importer.py";Target=(Join-Path $back "app\importer.py")}
)
foreach ($item in $targets) {
    if (Test-Path $item.Target) { Copy-Item $item.Target "$($item.Target).bak-$stamp" -Force }
    Copy-Item (Join-Path $package $item.Source) $item.Target -Force
    Write-Host "Actualizado: $($item.Target)" -ForegroundColor Green
}

Write-Host "" 
Write-Host "Listo. Reinicia frontend y backend, luego subi los cambios a GitHub." -ForegroundColor Green
Read-Host "Presiona ENTER para cerrar"
