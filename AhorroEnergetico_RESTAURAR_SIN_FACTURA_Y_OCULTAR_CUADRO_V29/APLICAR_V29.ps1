$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - SIN FACTURA + OCULTAR CUADRO V29" -ForegroundColor Cyan
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
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))){
    $front=$c
    break
  }
}
if(-not $front){throw "No encontre front\app\page.tsx y globals.css."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White
Write-Host ""

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_v29_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

# ---------------------------------------------------------
# 1) REVERTIR V28: ese CSS ocultó también la nueva pestaña.
# ---------------------------------------------------------
$css=Get-Content $cssPath -Raw
$css2=[regex]::Replace(
  $css,
  '(?s)/\* === OCULTAR CUADRO FALTANTES V28 START === \*/.*?/\* === OCULTAR CUADRO FALTANTES V28 END === \*/',
  ''
)

if($css2 -ne $css){
  Write-Host "[OK] CSS V28 eliminado. La subpestaña Sin factura vuelve a mostrarse." -ForegroundColor Green
}else{
  Write-Host "[INFO] No encontre bloque CSS V28; continuo." -ForegroundColor Yellow
}

Set-Content $cssPath $css2 -Encoding UTF8

# ---------------------------------------------------------
# 2) OCULTAR SOLO EL COMPONENTE VIEJO, SIN BORRAR CONTENEDORES.
#    Reemplazamos únicamente la llamada exacta por null.
# ---------------------------------------------------------
$page=Get-Content $pagePath -Raw
$before=$page

$patterns=@(
  '<MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod}/>',
  '<MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod} />'
)

$replaced=$false
foreach($old in $patterns){
  if($page.Contains($old)){
    $page=$page.Replace($old,'{null}')
    $replaced=$true
    break
  }
}

# Fallback flexible: SOLO el tag autocerrado MissingInvoiceTable.
if(-not $replaced){
  $rx=New-Object System.Text.RegularExpressions.Regex(
    '<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}\s+period=\{controlPeriod\}\s*/>',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if($rx.IsMatch($page)){
    $page=$rx.Replace($page,'{null}',1)
    $replaced=$true
  }
}

if($replaced){
  Write-Host "[OK] Cuadro viejo de faltantes desactivado de forma segura." -ForegroundColor Green
}else{
  Write-Host "[INFO] No encontre MissingInvoiceTable exacto. No toque JSX." -ForegroundColor Yellow
}

Set-Content $pagePath $page -Encoding UTF8

# ---------------------------------------------------------
# 3) VERIFICACIONES
# ---------------------------------------------------------
$checkPage=Get-Content $pagePath -Raw
$checkCss=Get-Content $cssPath -Raw

$hasSubTab=$checkPage -match 'invoiceSubTab==="missing"'
$hasSubPage=$checkPage -match 'invoice-missing-subpage'
$v28Gone=$checkCss -notmatch 'OCULTAR CUADRO FALTANTES V28 START'
$oldBoxGone=$checkPage -notmatch '<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Subpestaña Sin factura:   $hasSubTab"
Write-Host "  Lista Sin factura:        $hasSubPage"
Write-Host "  CSS V28 eliminado:        $v28Gone"
Write-Host "  Cuadro viejo desactivado: $oldBoxGone"

if(-not ($hasSubTab -and $hasSubPage -and $v28Gone)){
  throw "La verificacion de la subpestaña Sin factura fallo."
}

# Limpiar cache Vite
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
Write-Host " V29 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resultado esperado:" -ForegroundColor White
Write-Host " - Facturas recibidas funciona normal" -ForegroundColor Green
Write-Host " - Sin factura vuelve a mostrar la lista" -ForegroundColor Green
Write-Host " - El cuadro grande 'Faltan X facturas' ya no aparece" -ForegroundColor Green
Write-Host ""
Write-Host "Backup:" -ForegroundColor DarkGray
Write-Host "  $backup" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Ahora:" -ForegroundColor Cyan
Write-Host "  cd `"$front`"" -ForegroundColor White
Write-Host "  npm run dev" -ForegroundColor White
Write-Host "  Ctrl + F5" -ForegroundColor White

Read-Host "ENTER para cerrar"
