$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - RESTAURAR PRE V25 V27" -ForegroundColor Cyan
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

# Guardar estado roto actual
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$brokenBackup=Join-Path $front "backup_estado_roto_v27_$stamp"
New-Item -ItemType Directory -Path $brokenBackup -Force | Out-Null
Copy-Item $pagePath (Join-Path $brokenBackup "page.tsx") -Force

# El V25 creo un backup justo ANTES de romper page.tsx.
$preV25 = Get-ChildItem $front -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "backup_quitar_cuadro_faltantes_v25_*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if(-not $preV25){
  throw "No encontre backup_quitar_cuadro_faltantes_v25_*. Ese es el backup exacto previo al V25."
}

$source=Join-Path $preV25.FullName "page.tsx"
if(-not (Test-Path $source)){
  throw "El backup V25 existe pero no contiene page.tsx."
}

Write-Host "[OK] Backup exacto anterior al V25:" -ForegroundColor Green
Write-Host "  $source" -ForegroundColor White

# Restaurar exactamente el archivo sano anterior al V25.
Copy-Item $source $pagePath -Force
Write-Host "[OK] page.tsx restaurado." -ForegroundColor Green

# No borramos el cuadro todavía: primero recuperamos una app compilable.
# Solo limpiamos caches.
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
$hasSubtabs=$check -match 'invoice-subtabs'
$hasInvoices=$check -match 'tab==="invoices"'
$hasMissingSub=$check -match 'invoiceSubTab==="missing"'

Write-Host ""
Write-Host "Verificacion del archivo restaurado:" -ForegroundColor Cyan
Write-Host "  Vista Facturas:        $hasInvoices"
Write-Host "  Subpestanas:           $hasSubtabs"
Write-Host "  Subpestana Sin factura:$hasMissingSub"

if(-not $hasInvoices){
  throw "El backup restaurado no contiene la vista Facturas esperada."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V27 RESTAURADO CORRECTAMENTE" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Este V27 NO intenta volver a borrar el cuadro de faltantes." -ForegroundColor Yellow
Write-Host "Primero recuperamos la aplicacion sin errores de JSX." -ForegroundColor White
Write-Host ""
Write-Host "Ahora ejecuta:" -ForegroundColor Cyan
Write-Host "  cd `"$front`"" -ForegroundColor White
Write-Host "  npm run dev" -ForegroundColor White
Write-Host ""
Write-Host "Si abre bien, hacemos el siguiente fix para ocultar ese cuadro sin tocar JSX." -ForegroundColor Green
Write-Host ""
Write-Host "Backup del estado roto actual:" -ForegroundColor DarkGray
Write-Host "  $brokenBackup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
