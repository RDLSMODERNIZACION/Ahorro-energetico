$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - SCROLL REAL UNIFICADO V5" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# Detecta FRONT tanto si ejecutas desde la raiz como desde front.
$here = (Get-Location).Path
$candidates = @(
    $here,
    (Join-Path $here "front"),
    (Split-Path -Parent $here),
    (Join-Path (Split-Path -Parent $here) "front")
) | Select-Object -Unique

$front = $null
foreach($c in $candidates){
    if((Test-Path (Join-Path $c "app\page.tsx")) -and
       (Test-Path (Join-Path $c "app\globals.css"))){
        $front = $c
        break
    }
}

if(-not $front){
    Write-Host "[ERROR] No encontre app\page.tsx y app\globals.css." -ForegroundColor Red
    Read-Host "ENTER para cerrar"
    exit 1
}

$pagePath = Join-Path $front "app\page.tsx"
$cssPath  = Join-Path $front "app\globals.css"

Write-Host "[OK] Front:" -ForegroundColor Green
Write-Host "     $front" -ForegroundColor White

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $front "backup_scroll_real_v5_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath  (Join-Path $backup "globals.css") -Force

$page = Get-Content $pagePath -Raw

# Diagnostico rapido para saber que variante local tenes.
$hasInvoiceCall = $page -match '<InvoiceTable\b'
$hasMissingCall = $page -match '<MissingInvoiceTable\b'
$hasPendingProp = $page -match 'pendingMeters=\{visibleMissingPeriodMeters\}'
$hasWrapper     = $page -match 'className="invoice-unified-scroll"'

Write-Host ""
Write-Host "Diagnostico local:" -ForegroundColor Cyan
Write-Host "  InvoiceTable call:       $hasInvoiceCall"
Write-Host "  MissingInvoiceTable:     $hasMissingCall"
Write-Host "  pendingMeters en tabla:  $hasPendingProp"
Write-Host "  wrapper unificado:       $hasWrapper"
Write-Host ""

# CASO 1: siguen siendo dos componentes separados.
if($hasInvoiceCall -and $hasMissingCall -and -not $hasWrapper){
    # Busca dos llamadas JSX consecutivas sin depender del orden exacto de props.
    $pattern = '(?s)(<InvoiceTable\b[^>]*?/>)(\s*)(<MissingInvoiceTable\b[^>]*?/>)'
    if([regex]::IsMatch($page,$pattern)){
        $page = [regex]::Replace(
            $page,
            $pattern,
            '<div className="invoice-unified-scroll">$1$2$3</div>',
            1
        )
        Write-Host "[OK] Uni InvoiceTable + MissingInvoiceTable en un solo contenedor." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Veo ambas llamadas pero no estan consecutivas." -ForegroundColor Red
        Write-Host "No modifico page.tsx para evitar romperlo." -ForegroundColor Yellow
        Read-Host "ENTER para cerrar"
        exit 1
    }
}
elseif($hasWrapper){
    Write-Host "[OK] El wrapper unificado ya existe." -ForegroundColor DarkGreen
}
elseif($hasPendingProp){
    # CASO 2: V3 ya metio pendientes dentro del InvoiceTable.
    # En este caso no hacen falta dos componentes: envolvemos solo la tabla principal.
    $patternSingle = '(?s)(<InvoiceTable\b[^>]*?pendingMeters=\{visibleMissingPeriodMeters\}[^>]*?/>)'
    if([regex]::IsMatch($page,$patternSingle)){
        $page = [regex]::Replace(
            $page,
            $patternSingle,
            '<div className="invoice-unified-scroll">$1</div>',
            1
        )
        Write-Host "[OK] La tabla V3 ya era unica; agregue el contenedor de scroll real." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Detecte pendingMeters pero no pude envolver InvoiceTable." -ForegroundColor Red
        Read-Host "ENTER para cerrar"
        exit 1
    }
}
else{
    Write-Host "[ERROR] La estructura local es distinta a las versiones conocidas." -ForegroundColor Red
    Write-Host "Backup creado en: $backup" -ForegroundColor Yellow
    Read-Host "ENTER para cerrar"
    exit 1
}

Set-Content -Path $pagePath -Value $page -Encoding UTF8

# CSS directo en globals.css.
$css = Get-Content $cssPath -Raw
$css = [regex]::Replace(
    $css,
    '(?s)/\* === SCROLL REAL V5 START === \*/.*?/\* === SCROLL REAL V5 END === \*/',
    ''
)

$block = @'

/* === SCROLL REAL V5 START === */

/*
 UNA SOLA VENTANA DE SCROLL:
 - vertical dentro del bloque
 - horizontal dentro del mismo bloque
 - la barra horizontal queda visible al pie de la ventana
   sin tener que bajar toda la pagina.
*/
.invoice-unified-scroll{
  width:100% !important;
  max-width:100% !important;
  max-height:calc(100vh - 270px) !important;
  overflow:auto !important;
  position:relative !important;
  display:block !important;
  scrollbar-gutter:stable;
  overscroll-behavior:contain;
  -webkit-overflow-scrolling:touch;
}

/* Los hijos NO pueden tener su propio scroll. */
.invoice-unified-scroll > .invoice-admin-scroll,
.invoice-unified-scroll > .missing-table{
  overflow:visible !important;
  max-height:none !important;
  width:max-content !important;
  min-width:100% !important;
}

/* Las dos partes usan el mismo ancho. */
.invoice-unified-scroll .invoice-admin{
  width:1700px !important;
  min-width:1700px !important;
  max-width:1700px !important;
}

/* Cabecera visible al bajar dentro del listado. */
.invoice-unified-scroll .invoice-admin-scroll .invoice-admin thead th{
  position:sticky !important;
  top:0 !important;
  z-index:10 !important;
  background:#f8faf9 !important;
}

/* Medidor fijo al desplazarse lateralmente. */
.invoice-unified-scroll .invoice-admin th:nth-child(1),
.invoice-unified-scroll .invoice-admin td:nth-child(1){
  position:sticky !important;
  left:0 !important;
  min-width:190px !important;
  width:190px !important;
  z-index:7 !important;
  background:#fff !important;
}

/* Servicio fijo al desplazarse lateralmente. */
.invoice-unified-scroll .invoice-admin th:nth-child(2),
.invoice-unified-scroll .invoice-admin td:nth-child(2){
  position:sticky !important;
  left:190px !important;
  min-width:300px !important;
  width:300px !important;
  z-index:7 !important;
  background:#fff !important;
  box-shadow:8px 0 12px -12px rgba(23,33,29,.65);
}

.invoice-unified-scroll .invoice-admin thead th:nth-child(1),
.invoice-unified-scroll .invoice-admin thead th:nth-child(2){
  z-index:15 !important;
  background:#f8faf9 !important;
}

/* Pendientes mantienen el gris. */
.invoice-unified-scroll .missing-invoice-row td:nth-child(1),
.invoice-unified-scroll .missing-invoice-row td:nth-child(2),
.invoice-unified-scroll .pending-invoice-row td:nth-child(1),
.invoice-unified-scroll .pending-invoice-row td:nth-child(2){
  background:#eef0ef !important;
}

/* Si sigue existiendo MissingInvoiceTable, ocupa el mismo ancho. */
.invoice-unified-scroll .missing-table,
.invoice-unified-scroll .missing-table-title{
  width:1700px !important;
  min-width:1700px !important;
}

/* Scroll visible. */
.invoice-unified-scroll::-webkit-scrollbar{
  width:13px !important;
  height:18px !important;
}
.invoice-unified-scroll::-webkit-scrollbar-track{
  background:#e4ece8 !important;
}
.invoice-unified-scroll::-webkit-scrollbar-thumb{
  background:#557866 !important;
  border:4px solid #e4ece8 !important;
  border-radius:999px !important;
}
.invoice-unified-scroll::-webkit-scrollbar-thumb:hover{
  background:#345846 !important;
}

.invoice-unified-scroll{
  scrollbar-width:auto;
  scrollbar-color:#557866 #e4ece8;
}

/* === SCROLL REAL V5 END === */
'@

$css = $css.TrimEnd() + "`r`n" + $block + "`r`n"
Set-Content -Path $cssPath -Value $css -Encoding UTF8

# Verificacion.
$page2 = Get-Content $pagePath -Raw
$css2 = Get-Content $cssPath -Raw
if(($page2 -notmatch 'invoice-unified-scroll') -or ($css2 -notmatch 'SCROLL REAL V5 START')){
    throw "La verificacion final fallo."
}

# Limpiar cache para que SI o SI recomponga.
$next = Join-Path $front ".next"
if(Test-Path $next){
    Remove-Item $next -Recurse -Force
    Write-Host "[OK] Cache .next eliminada." -ForegroundColor Green
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " CAMBIO V5 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backup:" -ForegroundColor Yellow
Write-Host "  $backup" -ForegroundColor White
Write-Host ""
Write-Host "Ahora ejecuta:" -ForegroundColor Cyan
Write-Host "  npm run dev" -ForegroundColor White
Write-Host ""
Write-Host "Y en Chrome:" -ForegroundColor Cyan
Write-Host "  Ctrl + F5" -ForegroundColor White
Write-Host ""
Read-Host "ENTER para cerrar"
