$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Get-Location).Path

if (-not (Test-Path (Join-Path $repo "front\app\page.tsx"))) {
    throw "Ejecutá este script parado en la raíz de Ahorro-energetico."
}

function Copy-IfDifferent {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    $src = [System.IO.Path]::GetFullPath($Source)
    $dst = [System.IO.Path]::GetFullPath($Destination)

    if ($src.TrimEnd('\') -ieq $dst.TrimEnd('\')) {
        Write-Host "OK - $([System.IO.Path]::GetFileName($dst)) ya está en su ubicación final." -ForegroundColor DarkGreen
        return
    }

    if (-not (Test-Path $src)) {
        throw "No encontré el archivo origen: $src"
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "OK - Copiado: $([System.IO.Path]::GetFileName($dst))" -ForegroundColor Green
}

$srcPanel = Join-Path $scriptDir "front\app\public-lighting-panel.tsx"
$srcCss   = Join-Path $scriptDir "front\app\public-lighting-panel.css"
$dstPanel = Join-Path $repo "front\app\public-lighting-panel.tsx"
$dstCss   = Join-Path $repo "front\app\public-lighting-panel.css"

# Si el ZIP se descomprimió directamente sobre el repo, origen y destino son iguales.
# En ese caso no copiamos: los archivos ya quedaron instalados al descomprimir.
Copy-IfDifferent -Source $srcPanel -Destination $dstPanel
Copy-IfDifferent -Source $srcCss -Destination $dstCss

if (-not (Test-Path $dstPanel)) { throw "Falta front\app\public-lighting-panel.tsx" }
if (-not (Test-Path $dstCss))   { throw "Falta front\app\public-lighting-panel.css" }

Write-Host ""
Write-Host "ALUMBRADO PUBLICO - ANALISIS INDIVIDUAL V2 aplicado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "Para probar:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
