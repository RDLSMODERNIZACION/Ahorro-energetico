$ErrorActionPreference = "Stop"

$Package = Split-Path -Parent $MyInvocation.MyCommand.Path
$Project = Split-Path -Parent $Package

$Targets = @(
    @{
        Source = Join-Path $Package "payload\back\app\routers\catalog.py"
        Target = Join-Path $Project "back\app\routers\catalog.py"
    },
    @{
        Source = Join-Path $Package "payload\back\app\importer.py"
        Target = Join-Path $Project "back\app\importer.py"
    },
    @{
        Source = Join-Path $Package "payload\front\app\page.tsx"
        Target = Join-Path $Project "front\app\page.tsx"
    }
)

foreach ($Item in $Targets) {
    $TargetDirectory = Split-Path -Parent $Item.Target
    if (-not (Test-Path $TargetDirectory)) {
        throw "No se encontro la carpeta esperada: $TargetDirectory"
    }
}

foreach ($Item in $Targets) {
    Copy-Item -LiteralPath $Item.Source -Destination $Item.Target -Force
    Write-Host "Actualizado: $($Item.Target)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Actualizacion aplicada correctamente." -ForegroundColor Green
Write-Host "Las posibles bajas siguen contando como facturas pendientes y se muestran en amarillo."
Write-Host "Solo una BAJA CONFIRMADA deja de exigir la factura mensual."

