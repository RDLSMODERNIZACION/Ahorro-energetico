$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - DIAGNOSTICO VISUAL V6" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

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
       (Test-Path (Join-Path $c "app\globals.css")) -and
       (Test-Path (Join-Path $c "package.json"))){
        $front = $c
        break
    }
}

if(-not $front){
    Write-Host "[ERROR] No encontre el front." -ForegroundColor Red
    Read-Host "ENTER para cerrar"
    exit 1
}

$pagePath = Join-Path $front "app\page.tsx"
$cssPath = Join-Path $front "app\globals.css"
$packagePath = Join-Path $front "package.json"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$pkg = Get-Content $packagePath -Raw
if($pkg -match '"dev"\s*:\s*"([^"]+)"'){
    Write-Host "[INFO] npm run dev ejecuta: $($Matches[1])" -ForegroundColor Yellow
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $front "backup_diagnostico_v6_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page = Get-Content $pagePath -Raw

# Asegura wrapper aun si ya tenes la V3.
if($page -notmatch 'className="invoice-unified-scroll"'){
    if($page -match 'pendingMeters=\{visibleMissingPeriodMeters\}'){
        $pattern = '(?s)(<InvoiceTable\b[^>]*?pendingMeters=\{visibleMissingPeriodMeters\}[^>]*?/>)'
        if([regex]::IsMatch($page,$pattern)){
            $page = [regex]::Replace($page,$pattern,'<div className="invoice-unified-scroll">$1</div>',1)
            Write-Host "[OK] Wrapper agregado alrededor de InvoiceTable V3." -ForegroundColor Green
        } else {
            throw "Detecte V3 pero no pude envolver InvoiceTable."
        }
    } elseif(($page -match '<InvoiceTable\b') -and ($page -match '<MissingInvoiceTable\b')) {
        $pattern = '(?s)(<InvoiceTable\b[^>]*?/>)(\s*)(<MissingInvoiceTable\b[^>]*?/>)'
        if([regex]::IsMatch($page,$pattern)){
            $page = [regex]::Replace($page,$pattern,'<div className="invoice-unified-scroll">$1$2$3</div>',1)
            Write-Host "[OK] Wrapper agregado alrededor de ambas tablas." -ForegroundColor Green
        } else {
            throw "Veo ambas tablas pero no pude envolverlas."
        }
    } else {
        throw "No reconozco la estructura actual de la vista Facturas."
    }
} else {
    Write-Host "[OK] Wrapper invoice-unified-scroll ya existe." -ForegroundColor DarkGreen
}

Set-Content -Path $pagePath -Value $page -Encoding UTF8

$css = Get-Content $cssPath -Raw
$css = [regex]::Replace(
    $css,
    '(?s)/\* === DIAGNOSTICO V6 START === \*/.*?/\* === DIAGNOSTICO V6 END === \*/',
    ''
)

$block = @'

/* === DIAGNOSTICO V6 START === */

/* Marca visual inequívoca: si no aparece, NO estás viendo este front. */
body::after{
  content:"V6 ACTIVO";
  position:fixed;
  right:18px;
  bottom:18px;
  z-index:999999;
  background:#b91c1c;
  color:#fff;
  font:800 12px/1 ui-sans-serif,system-ui,sans-serif;
  letter-spacing:.08em;
  padding:10px 13px;
  border-radius:8px;
  box-shadow:0 8px 24px rgba(0,0,0,.28);
  pointer-events:none;
}

/* Un único viewport real para la tabla. */
.invoice-unified-scroll{
  display:block !important;
  width:100% !important;
  max-width:100% !important;
  height:560px !important;
  max-height:560px !important;
  overflow-x:auto !important;
  overflow-y:auto !important;
  position:relative !important;
  border-top:3px solid #b91c1c !important;
  border-bottom:3px solid #b91c1c !important;
  scrollbar-gutter:stable both-edges;
}

/* Nada adentro crea su propio scroll. */
.invoice-unified-scroll .invoice-admin-scroll,
.invoice-unified-scroll .missing-table{
  overflow:visible !important;
  max-height:none !important;
  width:max-content !important;
  min-width:1800px !important;
}

/* Fuerza ancho mayor al viewport para que SIEMPRE exista scroll horizontal. */
.invoice-unified-scroll .invoice-admin{
  width:1800px !important;
  min-width:1800px !important;
  max-width:1800px !important;
}

/* Barra grande y contrastada */
.invoice-unified-scroll::-webkit-scrollbar{
  width:16px !important;
  height:20px !important;
}
.invoice-unified-scroll::-webkit-scrollbar-track{
  background:#dbe4df !important;
}
.invoice-unified-scroll::-webkit-scrollbar-thumb{
  background:#14532d !important;
  border:3px solid #dbe4df !important;
  border-radius:999px !important;
}
.invoice-unified-scroll{
  scrollbar-width:auto !important;
  scrollbar-color:#14532d #dbe4df !important;
}

/* Cabecera fija */
.invoice-unified-scroll thead th{
  position:sticky !important;
  top:0 !important;
  z-index:20 !important;
  background:#f8faf9 !important;
}

/* Medidor fijo */
.invoice-unified-scroll .invoice-admin th:nth-child(1),
.invoice-unified-scroll .invoice-admin td:nth-child(1){
  position:sticky !important;
  left:0 !important;
  z-index:12 !important;
  width:190px !important;
  min-width:190px !important;
  background:#fff !important;
}

/* Servicio fijo */
.invoice-unified-scroll .invoice-admin th:nth-child(2),
.invoice-unified-scroll .invoice-admin td:nth-child(2){
  position:sticky !important;
  left:190px !important;
  z-index:12 !important;
  width:300px !important;
  min-width:300px !important;
  background:#fff !important;
  box-shadow:8px 0 12px -12px rgba(23,33,29,.65);
}

.invoice-unified-scroll thead th:nth-child(1),
.invoice-unified-scroll thead th:nth-child(2){
  z-index:30 !important;
  background:#f8faf9 !important;
}

.invoice-unified-scroll .pending-invoice-row td:nth-child(1),
.invoice-unified-scroll .pending-invoice-row td:nth-child(2),
.invoice-unified-scroll .missing-invoice-row td:nth-child(1),
.invoice-unified-scroll .missing-invoice-row td:nth-child(2){
  background:#eef0ef !important;
}

/* === DIAGNOSTICO V6 END === */
'@

$css = $css.TrimEnd() + "`r`n" + $block + "`r`n"
Set-Content -Path $cssPath -Value $css -Encoding UTF8

# Borra caches reales de Vite/vinext.
$pathsToDelete = @(
    (Join-Path $front "node_modules\.vite"),
    (Join-Path $front ".vite"),
    (Join-Path $front ".vinext"),
    (Join-Path $front ".next"),
    (Join-Path $front "dist")
)

foreach($p in $pathsToDelete){
    if(Test-Path $p){
        Remove-Item $p -Recurse -Force
        Write-Host "[OK] Cache eliminada: $p" -ForegroundColor Green
    }
}

# Mata procesos Node que estén escuchando puertos de desarrollo comunes.
Write-Host ""
Write-Host "[INFO] Procesos Node escuchando puertos:" -ForegroundColor Cyan
try {
    $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
      Where-Object { $_.LocalPort -in @(3000,3001,4173,5173,5174,5175) }

    if($listeners){
        foreach($l in $listeners){
            $proc = Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue
            Write-Host ("  Puerto {0} -> PID {1} -> {2}" -f $l.LocalPort,$l.OwningProcess,$proc.ProcessName) -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Ninguno en 3000/3001/4173/5173/5174/5175" -ForegroundColor DarkGray
    }
} catch {}

$page2 = Get-Content $pagePath -Raw
$css2 = Get-Content $cssPath -Raw
if(($page2 -match 'invoice-unified-scroll') -and ($css2 -match 'V6 ACTIVO')){
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host " V6 ESCRITO CORRECTAMENTE EN TU FRONT" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
} else {
    throw "La verificacion del V6 fallo."
}

Write-Host ""
Write-Host "IMPORTANTE:" -ForegroundColor Yellow
Write-Host "1) Cerra TODOS los npm run dev abiertos." -ForegroundColor White
Write-Host "2) Desde esta carpeta ejecuta:" -ForegroundColor White
Write-Host "   cd `"$front`"" -ForegroundColor Cyan
Write-Host "   npm run dev" -ForegroundColor Cyan
Write-Host "3) Abri EXACTAMENTE la URL que Vite muestre en 'Local:'." -ForegroundColor White
Write-Host "4) Hace Ctrl+F5." -ForegroundColor White
Write-Host ""
Write-Host "Si estas viendo este front, abajo a la derecha DEBE aparecer:" -ForegroundColor Yellow
Write-Host "   V6 ACTIVO" -ForegroundColor Red
Write-Host ""
Write-Host "Si NO aparece V6 ACTIVO, el navegador está mostrando otra app/otro puerto." -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Write-Host ""
Read-Host "ENTER para cerrar"
