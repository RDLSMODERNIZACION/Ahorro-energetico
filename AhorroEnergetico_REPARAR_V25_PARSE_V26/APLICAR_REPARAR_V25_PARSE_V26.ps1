$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - REPARAR PARSE V26" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@(
  $here,
  (Join-Path $here "front"),
  (Split-Path -Parent $here),
  (Join-Path (Split-Path -Parent $here) "front")
) | Select-Object -Unique

$front=$null
foreach($c in $candidates){
  if(Test-Path (Join-Path $c "app\page.tsx")){
    $front=$c
    break
  }
}
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White
Write-Host ""

# Backup del estado roto actual.
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$brokenBackup=Join-Path $front "backup_estado_roto_v26_$stamp"
New-Item -ItemType Directory -Path $brokenBackup -Force | Out-Null
Copy-Item $pagePath (Join-Path $brokenBackup "page.tsx") -Force

# Buscar el backup más reciente ANTERIOR a V25.
$backupCandidates = Get-ChildItem $front -Directory -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Name -like "backup_facturas_subpestanas_v24_*" -or
    $_.Name -like "backup_resumen_mes_ia_v22_*" -or
    $_.Name -like "backup_reparar_dashboard_v21_*"
  } |
  Sort-Object LastWriteTime -Descending

$restoreSource=$null
foreach($b in $backupCandidates){
  $candidate=Join-Path $b.FullName "page.tsx"
  if(Test-Path $candidate){
    $content=Get-Content $candidate -Raw
    if(($content -match 'invoice-subtabs') -and ($content -match 'tab==="invoices"')){
      $restoreSource=$candidate
      break
    }
  }
}

if(-not $restoreSource){
  throw "No encontre un backup valido de V24/V22 para restaurar page.tsx."
}

Write-Host "[OK] Restaurando desde:" -ForegroundColor Green
Write-Host "  $restoreSource" -ForegroundColor White
Copy-Item $restoreSource $pagePath -Force

$page=Get-Content $pagePath -Raw

# Quitar SOLAMENTE el componente MissingInvoiceTable, sin tocar contenedores JSX.
$before=$page

$page=[regex]::Replace(
  $page,
  '<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}\s+period=\{controlPeriod\}\s*/>',
  ''
)

# Si el cuadro superior de faltantes usa otro componente o bloque simple,
# lo ocultamos por CSS/clase después en vez de borrar estructura JSX.
# No hacemos regex destructivo de secciones completas.

Set-Content $pagePath $page -Encoding UTF8

# Verificación básica de estructura esperada.
$check=Get-Content $pagePath -Raw
$okFacturas=$check -match 'invoice-subtabs'
$okReceived=$check -match 'invoiceSubTab==="received"'
$okMissing=$check -match 'invoiceSubTab==="missing"'
$badComponent=$check -match '<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Subpestanas Facturas: $okFacturas"
Write-Host "  Recibidas:            $okReceived"
Write-Host "  Sin factura:          $okMissing"
Write-Host "  MissingInvoiceTable:  $badComponent"

if(-not ($okFacturas -and $okReceived -and $okMissing) -or $badComponent){
  throw "La verificacion estructural no paso."
}

# Si existe un bloque visual con texto 'Faltan ... facturas', lo ocultamos vía CSS,
# evitando volver a romper JSX.
$cssPath=Join-Path $front "app\globals.css"
if(Test-Path $cssPath){
  $css=Get-Content $cssPath -Raw
  $css=[regex]::Replace($css,'(?s)/\* === OCULTAR CUADRO FALTANTES V26 START === \*/.*?/\* === OCULTAR CUADRO FALTANTES V26 END === \*/','')
  $block=@'

/* === OCULTAR CUADRO FALTANTES V26 START === */
/* Se oculta el bloque visual de faltantes dentro de Facturas recibidas.
   Los faltantes quedan en la subpestaña "Sin factura". */
.invoice-missing-summary-old,
.missing-period-panel,
.missing-period,
.missing-invoices-panel{
  display:none !important;
}
/* === OCULTAR CUADRO FALTANTES V26 END === */
'@
  $css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
  Set-Content $cssPath $css -Encoding UTF8
}

foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V26 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Restaure el page.tsx sano previo al V25 y quite solamente MissingInvoiceTable." -ForegroundColor Green
Write-Host "No hice reemplazos destructivos de secciones JSX." -ForegroundColor Green
Write-Host ""
Write-Host "Backup del estado roto:" -ForegroundColor DarkGray
Write-Host "  $brokenBackup" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Ahora ejecuta:" -ForegroundColor Cyan
Write-Host "  cd `"$front`"" -ForegroundColor White
Write-Host "  npm run dev" -ForegroundColor White

Read-Host "ENTER para cerrar"
