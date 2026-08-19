$ErrorActionPreference = "Stop"

Write-Host "" 
Write-Host "==========================================" -ForegroundColor DarkGreen
Write-Host "  CAMBIO: IDENTIDAD ENERGETICA MUNICIPAL" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor DarkGreen
Write-Host ""

$project = $null
$candidates = @(
    $PSScriptRoot,
    (Split-Path $PSScriptRoot -Parent),
    (Get-Location).Path
) | Select-Object -Unique

foreach ($candidate in $candidates) {
    if ((Test-Path (Join-Path $candidate "package.json")) -and
        (Test-Path (Join-Path $candidate "app"))) {
        $project = $candidate
        break
    }
}

if (-not $project) {
    Write-Host "No encontre el proyecto." -ForegroundColor Red
    Write-Host "Extrae este ZIP dentro de la carpeta Ahorro-energetico y ejecutalo nuevamente."
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}

$source = Join-Path $PSScriptRoot "payload\page.tsx"
$target = Join-Path $project "app\page.tsx"
$backup = Join-Path $project "app\page.tsx.backup"

if (-not (Test-Path $source)) {
    Write-Host "Falta el archivo payload\page.tsx." -ForegroundColor Red
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}

if (Test-Path $target) {
    Copy-Item $target $backup -Force
    Write-Host "Copia de seguridad creada: app\page.tsx.backup" -ForegroundColor Yellow
}

Copy-Item $source $target -Force

Write-Host ""
Write-Host "CAMBIO APLICADO CORRECTAMENTE" -ForegroundColor Green
Write-Host "Se elimino DIRAC y ahora figura Gestion Energetica Municipal."
Write-Host "No hace falta ejecutar npm install nuevamente."
Write-Host ""
Read-Host "Presiona ENTER para cerrar"
