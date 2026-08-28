$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " Ahorro Energetico - Scroll unificado facturas V2" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @(
    (Get-Location).Path,
    (Join-Path (Get-Location).Path "front"),
    (Split-Path -Parent $scriptDir),
    (Join-Path (Split-Path -Parent $scriptDir) "front")
) | Select-Object -Unique

$front = $null
foreach ($candidate in $candidates) {
    $page = Join-Path $candidate "app\page.tsx"
    $layout = Join-Path $candidate "app\layout.tsx"
    if ((Test-Path $page) -and (Test-Path $layout)) {
        $front = $candidate
        break
    }
}

if (-not $front) {
    Write-Host "No pude detectar la carpeta front." -ForegroundColor Yellow
    Write-Host "Ejecuta este script desde Ahorro-energetico\front" -ForegroundColor Yellow
    Read-Host "Presiona ENTER para salir"
    exit 1
}

Write-Host "Front detectado: $front" -ForegroundColor Green

$appDir = Join-Path $front "app"
$pagePath = Join-Path $appDir "page.tsx"
$layoutPath = Join-Path $appDir "layout.tsx"
$cssTarget = Join-Path $appDir "table-scroll-unified.css"
$cssSource = Join-Path $scriptDir "table-scroll-unified.css"

if (-not (Test-Path $cssSource)) {
    throw "Falta table-scroll-unified.css en el paquete."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $front "backup_scroll_unificado_$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

Copy-Item $pagePath (Join-Path $backupDir "page.tsx") -Force
Copy-Item $layoutPath (Join-Path $backupDir "layout.tsx") -Force
if (Test-Path $cssTarget) {
    Copy-Item $cssTarget (Join-Path $backupDir "table-scroll-unified.css") -Force
}

$page = Get-Content $pagePath -Raw

$old = '<InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} onSelect={openMeter}/><MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod}/>'
$new = '<div className="invoice-unified-scroll"><InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} onSelect={openMeter}/><MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod}/></div>'

if ($page.Contains($old)) {
    $page = $page.Replace($old, $new)
    Set-Content -Path $pagePath -Value $page -Encoding UTF8
    Write-Host "[OK] Facturas cargadas y pendientes ahora comparten el mismo scroll." -ForegroundColor Green
}
elseif ($page -match 'invoice-unified-scroll') {
    Write-Host "[OK] El contenedor unificado ya estaba aplicado." -ForegroundColor DarkGreen
}
else {
    Write-Host "[ERROR] No encontre el bloque esperado en app\page.tsx." -ForegroundColor Red
    Write-Host "No hice cambios sobre page.tsx para evitar romper el front." -ForegroundColor Yellow
    Read-Host "Presiona ENTER para salir"
    exit 1
}

Copy-Item $cssSource $cssTarget -Force
Write-Host "[OK] CSS V2 instalado." -ForegroundColor Green

$layout = Get-Content $layoutPath -Raw
if ($layout -notmatch 'table-scroll-unified\.css') {
    if ($layout -match 'import\s+"\./globals\.css";') {
        $layout = $layout -replace 'import\s+"\./globals\.css";', "import `"./globals.css`";`r`nimport `"./table-scroll-unified.css`";"
    }
    elseif ($layout -match "import\s+'\./globals\.css';") {
        $layout = $layout -replace "import\s+'\./globals\.css';", "import './globals.css';`r`nimport './table-scroll-unified.css';"
    }
    else {
        $layout = "import `"./table-scroll-unified.css`";`r`n" + $layout
    }
    Set-Content -Path $layoutPath -Value $layout -Encoding UTF8
    Write-Host "[OK] Import CSS agregado." -ForegroundColor Green
}
else {
    Write-Host "[OK] El import CSS ya estaba agregado." -ForegroundColor DarkGreen
}

Write-Host ""
Write-Host "FIX V2 APLICADO" -ForegroundColor Cyan
Write-Host "Ahora:" -ForegroundColor White
Write-Host " - Facturas cargadas y pendientes son un solo bloque" -ForegroundColor White
Write-Host " - Ambas se mueven juntas izquierda/derecha" -ForegroundColor White
Write-Host " - Hay una sola barra horizontal" -ForegroundColor White
Write-Host " - Medidor y Servicio quedan fijos" -ForegroundColor White
Write-Host ""
Write-Host "Backup: $backupDir" -ForegroundColor Yellow
Write-Host ""
Write-Host "Probar con:" -ForegroundColor Cyan
Write-Host "  npm run dev" -ForegroundColor White
Write-Host ""

Read-Host "Presiona ENTER para cerrar"
