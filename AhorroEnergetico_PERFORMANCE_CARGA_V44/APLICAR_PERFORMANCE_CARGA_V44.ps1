$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - PERFORMANCE CARGA V44" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$root=$null
foreach($c in @($here,(Split-Path -Parent $here))){
  if((Test-Path (Join-Path $c "front\app\page.tsx")) -and
     (Test-Path (Join-Path $c "back\app\routers\invoices.py"))){$root=$c;break}
}
if(-not $root){throw "No encontre front y back del proyecto."}

$pagePath=Join-Path $root "front\app\page.tsx"
$invoicePath=Join-Path $root "back\app\routers\invoices.py"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_performance_carga_v44_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $invoicePath (Join-Path $backup "invoices.py") -Force

# ================================================================
# BACKEND: respuesta de facturas más compacta + menos round trips
# ================================================================
$inv=Get-Content $invoicePath -Raw

$start=$inv.IndexOf('INVOICE_LIST_SELECT = (')
$end=$inv.IndexOf("`r`n`r`n@router.get", $start)
if($end -lt 0){$end=$inv.IndexOf("`n`n@router.get", $start)}
if($start -lt 0 -or $end -lt 0){throw "No encontre INVOICE_LIST_SELECT."}

$newSelect=@'
INVOICE_LIST_SELECT = (
    "id,organization_id,meter_id,invoice_number,"
    "period_start,period_end,issue_date,due_date,current_tariff_code,"
    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,total_amount,"
    "amount_due,billing_period,tariff_name,tariff_class,vat_amount,"
    "previous_debt_amount,"
    "meters(id,meter_number,nis,tracking_code,supply_number,contract_number,"
    "service_code,service_name,cadastral_number,current_tariff_code,"
    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,sites(name,address)),"
    "invoice_measurements(active_energy_kwh,reactive_energy_kvarh,demand_kw,"
    "power_factor,registered_demand_peak_kw,registered_demand_off_peak_kw,"
    "tangent_phi,reactive_surcharge_percent,meter_number,measurement_type),"
    "invoice_lines(concept_code,description,quantity,unit_price,net_amount)"
)
'@

$inv=$inv.Substring(0,$start)+$newSelect+$inv.Substring($end)

# 200 -> 1000 para evitar varias consultas internas a Supabase.
$inv=$inv.Replace('page_size = 200','page_size = 1000')

Set-Content $invoicePath $inv -Encoding UTF8

# ================================================================
# FRONT: evitar doble/triple carga del mismo dataset
# ================================================================
$page=Get-Content $pagePath -Raw

# Agregar ref de dataset cargado
$anchor='const invoiceFiltersInitialized=useRef(false);'
if($page.Contains($anchor) -and $page -notmatch 'loadedDataKey'){
  $page=$page.Replace($anchor,$anchor+"`r`n  "+'const loadedDataKey=useRef("");')
}

# Marcar el dataset apenas se resuelve la organización
$needle='const [m,i,o]=await Promise.all(['
if($page.Contains($needle) -and $page -notmatch 'loadedDataKey\.current=`\$\{s\.user\.id\}:\$\{target\}`'){
  $page=$page.Replace($needle,'loadedDataKey.current=`${s.user.id}:${target}`;'+"`r`n      "+$needle)
}

# Reemplazar useEffect de carga por versión con guard.
$old='useEffect(()=>{if(session)load(session,orgId)},[session,orgId,load]);'
$new='useEffect(()=>{if(!session)return;const key=orgId?`${session.user.id}:${orgId}`:"";if(key&&loadedDataKey.current===key)return;load(session,orgId)},[session,orgId,load]);'
if($page.Contains($old)){
  $page=$page.Replace($old,$new)
}elseif($page -notmatch 'loadedDataKey\.current===key'){
  throw "No encontre el useEffect de carga esperado."
}

Set-Content $pagePath $page -Encoding UTF8

# Limpiar caches
foreach($p in @(
  (Join-Path $root "front\.next"),
  (Join-Path $root "front\node_modules\.vite"),
  (Join-Path $root "front\.vite")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificación
$checkInv=Get-Content $invoicePath -Raw
$checkPage=Get-Content $pagePath -Raw

$okCompact=($checkInv -notmatch 'raw_data') -and ($checkInv -match 'page_size = 1000')
$okGuard=$checkPage -match 'loadedDataKey' -and $checkPage -match 'loadedDataKey\.current===key'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Facturas compactas: $okCompact"
Write-Host "  Supabase por bloques de 1000: $($checkInv -match 'page_size = 1000')"
Write-Host "  Evita recargas duplicadas: $okGuard"

if(-not $okCompact -or -not $okGuard){throw "La verificacion final fallo."}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V44 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Objetivo:" -ForegroundColor White
Write-Host " - bajar fuerte el tiempo de invoices?limit=5000" -ForegroundColor Green
Write-Host " - eliminar llamadas repetidas de missing/tariff" -ForegroundColor Green
Write-Host " - mantener los datos necesarios para dashboard, gráficos y análisis" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
