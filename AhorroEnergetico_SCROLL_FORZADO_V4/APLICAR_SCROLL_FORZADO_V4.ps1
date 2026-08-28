$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - SCROLL FORZADO UNIFICADO V4" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @(
    (Get-Location).Path,
    (Join-Path (Get-Location).Path "front"),
    (Split-Path -Parent $scriptDir),
    (Join-Path (Split-Path -Parent $scriptDir) "front")
) | Select-Object -Unique

$front = $null
foreach ($c in $candidates) {
    if ((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))) {
        $front = $c
        break
    }
}

if (-not $front) {
    Write-Host "[ERROR] No encontre la carpeta front." -ForegroundColor Red
    Write-Host "Abri PowerShell dentro de Ahorro-energetico\front y ejecuta de nuevo." -ForegroundColor Yellow
    Read-Host "ENTER para cerrar"
    exit 1
}

$pagePath = Join-Path $front "app\page.tsx"
$cssPath  = Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "     $front" -ForegroundColor White
Write-Host ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $front "backup_scroll_forzado_v4_$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath  (Join-Path $backup "globals.css") -Force

$page = Get-Content $pagePath -Raw

# Quita wrappers de intentos anteriores si existen, para no anidar scrolls.
$page = $page -replace '<div className="invoice-unified-scroll">\s*', ''
$page = $page -replace '\s*</div>(?=\s*\{selectedInvoice&&<MeterDetail)', ''

# Busca de manera flexible las dos llamadas consecutivas.
$pattern = '(?s)<InvoiceTable\s+invoices=\{filteredInvoices\}\s+assessments=\{assessments\}\s+tariffSavings=\{tariffSavings\}\s+onSelect=\{openMeter\}\s*/>\s*<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}\s+period=\{controlPeriod\}\s*/>'

if ([regex]::IsMatch($page, $pattern)) {
    $replacement = '<div className="invoice-unified-scroll"><InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} onSelect={openMeter}/><MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod}/></div>'
    $page = [regex]::Replace($page, $pattern, $replacement, 1)
    Write-Host "[OK] Encontre las dos tablas y las meti dentro del MISMO contenedor." -ForegroundColor Green
}
elseif ($page -match 'className="invoice-unified-scroll"') {
    Write-Host "[OK] El contenedor unificado ya existe en page.tsx." -ForegroundColor DarkGreen
}
else {
    Write-Host "[ERROR] No pude encontrar las llamadas InvoiceTable + MissingInvoiceTable." -ForegroundColor Red
    Write-Host "No sigo para no romper el archivo." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "PAGE: $pagePath" -ForegroundColor Yellow
    Read-Host "ENTER para cerrar"
    exit 1
}

Set-Content -Path $pagePath -Value $page -Encoding UTF8

# CSS directamente en globals.css: no depende de imports nuevos.
$css = Get-Content $cssPath -Raw

$markerStart = "/* === SCROLL FACTURAS UNIFICADO V4 START === */"
$markerEnd   = "/* === SCROLL FACTURAS UNIFICADO V4 END === */"

# Si ya existe un bloque V4, lo reemplazamos.
$css = [regex]::Replace(
    $css,
    '(?s)/\* === SCROLL FACTURAS UNIFICADO V4 START === \*/.*?/\* === SCROLL FACTURAS UNIFICADO V4 END === \*/',
    ''
)

$block = @'

/* === SCROLL FACTURAS UNIFICADO V4 START === */

/*
  IMPORTANTE:
  el scroll vive SOLO en .invoice-unified-scroll.
  Los dos bloques internos dejan de tener scroll propio.
*/
.invoice-unified-scroll{
  display:block !important;
  width:100% !important;
  max-width:100% !important;
  overflow-x:scroll !important;
  overflow-y:visible !important;
  position:relative !important;
  scrollbar-gutter:stable both-edges;
  overscroll-behavior-x:contain;
  padding-bottom:4px;
}

/* Anulamos el scroll individual de arriba y abajo */
.invoice-unified-scroll > .invoice-admin-scroll,
.invoice-unified-scroll > .missing-table{
  display:block !important;
  width:max-content !important;
  min-width:1700px !important;
  max-width:none !important;
  overflow:visible !important;
  max-height:none !important;
}

/* Las dos tablas deben medir exactamente lo mismo */
.invoice-unified-scroll .invoice-admin{
  width:1700px !important;
  min-width:1700px !important;
  max-width:1700px !important;
  table-layout:fixed;
}

/* Quita cualquier scrollbar interno previo */
.invoice-unified-scroll .invoice-admin-scroll::-webkit-scrollbar,
.invoice-unified-scroll .missing-table::-webkit-scrollbar{
  display:none !important;
}

/* Barra unica, visible y grande */
.invoice-unified-scroll::-webkit-scrollbar{
  height:18px !important;
}
.invoice-unified-scroll::-webkit-scrollbar-track{
  background:#e7eeea !important;
  border-top:1px solid #d7e0db;
}
.invoice-unified-scroll::-webkit-scrollbar-thumb{
  background:#527565 !important;
  border:4px solid #e7eeea !important;
  border-radius:999px !important;
}
.invoice-unified-scroll::-webkit-scrollbar-thumb:hover{
  background:#315847 !important;
}

/* Firefox */
.invoice-unified-scroll{
  scrollbar-width:auto;
  scrollbar-color:#527565 #e7eeea;
}

/* Medidor fijo */
.invoice-unified-scroll .invoice-admin th:nth-child(1),
.invoice-unified-scroll .invoice-admin td:nth-child(1){
  position:sticky !important;
  left:0 !important;
  z-index:8 !important;
  background:#fff !important;
}

/* Servicio fijo */
.invoice-unified-scroll .invoice-admin th:nth-child(2),
.invoice-unified-scroll .invoice-admin td:nth-child(2){
  position:sticky !important;
  left:190px !important;
  z-index:8 !important;
  background:#fff !important;
  box-shadow:8px 0 12px -12px rgba(23,33,29,.65);
}

/* Encabezados fijos por encima de las columnas */
.invoice-unified-scroll .invoice-admin thead th:nth-child(1),
.invoice-unified-scroll .invoice-admin thead th:nth-child(2){
  z-index:12 !important;
  background:#f8faf9 !important;
}

/* Pendientes conservan fondo gris aun con columnas sticky */
.invoice-unified-scroll .missing-invoice-row td:nth-child(1),
.invoice-unified-scroll .missing-invoice-row td:nth-child(2){
  background:#eef0ef !important;
}

/* La banda de pendientes ocupa el mismo ancho */
.invoice-unified-scroll .missing-table-title{
  width:1700px !important;
  min-width:1700px !important;
}

/* === SCROLL FACTURAS UNIFICADO V4 END === */
'@

$css = $css.TrimEnd() + "`r`n" + $block + "`r`n"
Set-Content -Path $cssPath -Value $css -Encoding UTF8

# Verificacion real
$pageCheck = Get-Content $pagePath -Raw
$cssCheck  = Get-Content $cssPath -Raw

if (($pageCheck -match 'invoice-unified-scroll') -and ($cssCheck -match 'SCROLL FACTURAS UNIFICADO V4 START')) {
    Write-Host "[OK] CAMBIO CONFIRMADO EN LOS ARCHIVOS." -ForegroundColor Green
} else {
    throw "La verificacion final fallo."
}

# Limpia cache de Next para obligar recompilacion.
$next = Join-Path $front ".next"
if (Test-Path $next) {
    Remove-Item $next -Recurse -Force
    Write-Host "[OK] Cache .next eliminada." -ForegroundColor Green
}

$cache = Join-Path $front "node_modules\.cache"
if (Test-Path $cache) {
    Remove-Item $cache -Recurse -Force
    Write-Host "[OK] Cache node_modules eliminada." -ForegroundColor Green
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " CAMBIO APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora hay UN SOLO scroll horizontal para:" -ForegroundColor White
Write-Host "  1. Facturas recibidas" -ForegroundColor Green
Write-Host "  2. Facturas pendientes" -ForegroundColor Green
Write-Host ""
Write-Host "Backup:" -ForegroundColor Yellow
Write-Host "  $backup" -ForegroundColor White
Write-Host ""
Write-Host "IMPORTANTE: cerra cualquier npm run dev que este abierto." -ForegroundColor Yellow
Write-Host "Luego ejecuta nuevamente:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  npm run dev" -ForegroundColor White
Write-Host ""
Write-Host "Y en el navegador hace Ctrl + F5." -ForegroundColor Cyan
Write-Host ""
Read-Host "ENTER para cerrar"
