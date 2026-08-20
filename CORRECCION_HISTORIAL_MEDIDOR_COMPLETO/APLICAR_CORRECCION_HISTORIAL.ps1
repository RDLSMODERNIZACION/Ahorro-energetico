$ErrorActionPreference = "Stop"

$Package = Split-Path -Parent $MyInvocation.MyCommand.Path
$Project = Split-Path -Parent $Package

$Targets = @(
    @{ Source = Join-Path $Package "payload\back\app\routers\invoices.py"; Target = Join-Path $Project "back\app\routers\invoices.py" },
    @{ Source = Join-Path $Package "payload\back\app\routers\catalog.py"; Target = Join-Path $Project "back\app\routers\catalog.py" },
    @{ Source = Join-Path $Package "payload\back\app\importer.py"; Target = Join-Path $Project "back\app\importer.py" },
    @{ Source = Join-Path $Package "payload\front\app\page.tsx"; Target = Join-Path $Project "front\app\page.tsx" },
    @{ Source = Join-Path $Package "payload\front\app\analysis-charts.tsx"; Target = Join-Path $Project "front\app\analysis-charts.tsx" }
)

foreach ($Item in $Targets) {
    $Directory = Split-Path -Parent $Item.Target
    if (-not (Test-Path $Directory)) {
        throw "No se encontro la carpeta esperada: $Directory"
    }
}

foreach ($Item in $Targets) {
    Copy-Item -LiteralPath $Item.Source -Destination $Item.Target -Force
    Write-Host "Actualizado: $($Item.Target)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Correccion aplicada correctamente." -ForegroundColor Green
Write-Host "El backend ahora pagina todas las facturas y los graficos reciben los 24 meses completos."
Write-Host "Incluye tambien el seguimiento obligatorio hasta confirmar una baja."

