$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - CLICK ALERTAS FIX V18" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
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

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_alertas_click_fix_v18_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

# El problema: selectedInvoice se abre/renderiza dentro de la vista Facturas.
# Desde IA se seteaba selectedInvoice pero se seguia en tab="ai", por eso visualmente no pasaba nada.
$old='const openMeter=(i:Invoice)=>{setSelectedInvoice(i);setSelectedMeter(i.meter_id)};'
$new='const openMeter=(i:Invoice)=>{setSelectedInvoice(i);setSelectedMeter(i.meter_id);setTab("invoices")};'

if($page.Contains($old)){
  $page=$page.Replace($old,$new)
  Write-Host "[OK] openMeter ahora cambia a Facturas antes de abrir el analisis." -ForegroundColor Green
}elseif($page -match 'const openMeter=\(i:Invoice\)=>\{[^}]*setTab\("invoices"\)'){
  Write-Host "[OK] openMeter ya tenia cambio a Facturas." -ForegroundColor DarkGreen
}else{
  # Fallback flexible
  $pattern='const openMeter=\(i:Invoice\)=>\{setSelectedInvoice\(i\);setSelectedMeter\(i\.meter_id\)\};'
  if([regex]::IsMatch($page,$pattern)){
    $page=[regex]::Replace($page,$pattern,$new,1)
    Write-Host "[OK] openMeter corregido con deteccion flexible." -ForegroundColor Green
  }else{
    throw "No encontre openMeter para modificar."
  }
}

# Fortalece openMeterById por si el V17 lo dejo.
if($page -match 'const openMeterById='){
  $page=[regex]::Replace(
    $page,
    'const openMeterById=\(meterId\?:string\)=>\{.*?\};',
    'const openMeterById=(meterId?:string)=>{if(!meterId)return;const i=[...invoices].filter(x=>x.meter_id===meterId).sort((a,b)=>invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];if(i)openMeter(i)};',
    1
  )
  Write-Host "[OK] openMeterById verificado." -ForegroundColor Green
}

Set-Content $pagePath $page -Encoding UTF8

# Limpia cache Vite
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if($check -match 'const openMeter=\(i:Invoice\)=>\{setSelectedInvoice\(i\);setSelectedMeter\(i\.meter_id\);setTab\("invoices"\)\};'){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V18 APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora al tocar una alerta:" -ForegroundColor White
  Write-Host "  1. Cambia a la vista Facturas" -ForegroundColor Green
  Write-Host "  2. Selecciona el medidor" -ForegroundColor Green
  Write-Host "  3. Abre el analisis individual" -ForegroundColor Green
  Write-Host ""
  Write-Host "Backup:" -ForegroundColor DarkGray
  Write-Host "  $backup" -ForegroundColor DarkGray
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
