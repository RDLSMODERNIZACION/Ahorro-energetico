$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Ahorro Energetico - Fix scroll de facturas" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Intentamos detectar la carpeta FRONT.
$candidates = @(
    (Get-Location).Path,
    (Join-Path (Get-Location).Path "front"),
    (Split-Path -Parent $scriptDir),
    (Join-Path (Split-Path -Parent $scriptDir) "front")
) | Select-Object -Unique

$front = $null
foreach ($candidate in $candidates) {
    $layout = Join-Path $candidate "app\layout.tsx"
    $page   = Join-Path $candidate "app\page.tsx"
    if ((Test-Path $layout) -and (Test-Path $page)) {
        $front = $candidate
        break
    }
}

if (-not $front) {
    Write-Host "No pude detectar automaticamente la carpeta front." -ForegroundColor Yellow
    Write-Host "Ejecuta este script desde:" -ForegroundColor Yellow
    Write-Host "  ...\Ahorro-energetico\front" -ForegroundColor White
    Write-Host ""
    Read-Host "Presiona ENTER para salir"
    exit 1
}

Write-Host "Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White
Write-Host ""

$appDir = Join-Path $front "app"
$layoutPath = Join-Path $appDir "layout.tsx"
$cssTarget = Join-Path $appDir "table-scroll-fix.css"
$cssSource = Join-Path $scriptDir "table-scroll-fix.css"

if (-not (Test-Path $cssSource)) {
    throw "Falta table-scroll-fix.css dentro del ZIP."
}

# Backup
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $front "backup_scroll_tabla_$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

Copy-Item $layoutPath (Join-Path $backupDir "layout.tsx") -Force
if (Test-Path $cssTarget) {
    Copy-Item $cssTarget (Join-Path $backupDir "table-scroll-fix.css") -Force
}

# Copia CSS
Copy-Item $cssSource $cssTarget -Force
Write-Host "[OK] CSS de scroll instalado." -ForegroundColor Green

# Agrega import al layout si no existe
$layout = Get-Content $layoutPath -Raw

if ($layout -notmatch 'table-scroll-fix\.css') {
    if ($layout -match 'import\s+"\./globals\.css";') {
        $layout = $layout -replace 'import\s+"\./globals\.css";', "import `"./globals.css`";`r`nimport `"./table-scroll-fix.css`";"
    }
    elseif ($layout -match "import\s+'\./globals\.css';") {
        $layout = $layout -replace "import\s+'\./globals\.css';", "import './globals.css';`r`nimport './table-scroll-fix.css';"
    }
    else {
        $layout = "import `"./table-scroll-fix.css`";`r`n" + $layout
    }

    Set-Content -Path $layoutPath -Value $layout -Encoding UTF8
    Write-Host "[OK] Import agregado en app\layout.tsx." -ForegroundColor Green
}
else {
    Write-Host "[OK] El import ya estaba agregado." -ForegroundColor DarkGreen
}

Write-Host ""
Write-Host "CAMBIO APLICADO" -ForegroundColor Cyan
Write-Host "Ahora la tabla de facturas tiene:" -ForegroundColor White
Write-Host " - Scroll horizontal visible" -ForegroundColor White
Write-Host " - Encabezado fijo" -ForegroundColor White
Write-Host " - Medidor fijo" -ForegroundColor White
Write-Host " - Servicio fijo" -ForegroundColor White
Write-Host " - Scroll vertical dentro de la tabla" -ForegroundColor White
Write-Host ""
Write-Host "Backup creado en:" -ForegroundColor Yellow
Write-Host "  $backupDir" -ForegroundColor White
Write-Host ""
Write-Host "Para probar:" -ForegroundColor Cyan
Write-Host "  npm run dev" -ForegroundColor White
Write-Host ""
Write-Host "Si usas Git:" -ForegroundColor Cyan
Write-Host "  git add ." -ForegroundColor White
Write-Host "  git commit -m `"Mejorar scroll tabla facturas`"" -ForegroundColor White
Write-Host "  git push" -ForegroundColor White
Write-Host ""

Read-Host "Presiona ENTER para cerrar"
