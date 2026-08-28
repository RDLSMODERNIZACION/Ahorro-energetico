$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - QUITAR CUADRO FALTANTES V25" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$front=$null
foreach($c in $candidates){
  if(Test-Path (Join-Path $c "app\page.tsx")){$front=$c;break}
}
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_quitar_cuadro_faltantes_v25_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw
$before=$page

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White
Write-Host ""

# 1) Quita llamada a MissingInvoiceTable si sigue en la vista de Facturas recibidas.
$page=[regex]::Replace(
  $page,
  '(?s)<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}\s+period=\{controlPeriod\}\s*/>',
  ''
)

# 2) Quita bloques JSX visibles que contienen el cuadro:
# "Faltan X facturas de..." + "Estos medidores no aparecen..."
$rx=New-Object System.Text.RegularExpressions.Regex(
  '(?s)<section\b[^>]*>.*?Faltan\s*\{?[^<]*facturas.*?Estos medidores no aparecen en el archivo del período seleccionado.*?</section>',
  [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$page=$rx.Replace($page,'',1)

# 3) Fallback por clases conocidas de paneles faltantes.
$patterns=@(
  '(?s)<div className="missing-period[^"]*".*?</div>\s*(?=<section className="panel invoices-admin|<div className="invoice-subtabs|<InvoiceTable)',
  '(?s)<section className="panel missing[^"]*".*?</section>\s*(?=<section className="panel invoices-admin|<InvoiceTable)',
  '(?s)<div className="missing-invoices[^"]*".*?</div>\s*(?=<section className="panel invoices-admin|<InvoiceTable)'
)
foreach($p in $patterns){
  $r=New-Object System.Text.RegularExpressions.Regex($p,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  if($r.IsMatch($page)){$page=$r.Replace($page,'',1)}
}

# 4) No borrar la subpestaña "Sin factura". Solo el cuadro redundante del periodo.
Set-Content $pagePath $page -Encoding UTF8

$check=Get-Content $pagePath -Raw
$stillVisible=($check -match 'Estos medidores no aparecen en el archivo del período seleccionado') -or ($check -match '<MissingInvoiceTable\s+meters=\{visibleMissingPeriodMeters\}')

if($stillVisible){
  Write-Host "[ERROR] El cuadro sigue referenciado en page.tsx." -ForegroundColor Red
  Write-Host "No hice mas reemplazos para evitar romper JSX." -ForegroundColor Yellow
  Write-Host "Backup: $backup" -ForegroundColor Yellow
  Read-Host "ENTER para cerrar"
  exit 1
}

if($page -eq $before){
  Write-Host "[INFO] El cuadro ya no estaba en el formato esperado, pero verifique que no quede su referencia principal." -ForegroundColor Yellow
}else{
  Write-Host "[OK] Cuadro de faltantes quitado de Facturas recibidas." -ForegroundColor Green
}

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V25 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Se saco el cuadro grande de 'Faltan X facturas'." -ForegroundColor Green
Write-Host "La informacion de faltantes queda solamente en la subpestana 'Sin factura'." -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
