$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if ((Test-Path (Join-Path $Root "back\app\routers\invoices.py")) -and (Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Root "front\app\page.tsx"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "back\app\routers\invoices.py")) -and (Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Parent "front\app\page.tsx"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$backend=Join-Path $Repo "back\app\routers\invoices.py"
$panel=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$page=Join-Path $Repo "front\app\page.tsx"
$css=Join-Path $Repo "front\app\globals.css"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_v20_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $backend $backup
Copy-Item $panel $backup
Copy-Item $page $backup
Copy-Item $css $backup

Copy-Item (Join-Path $Root "payload\back\app\routers\invoices.py") $backend -Force

# ==========================================================
# invoice-analysis-panel.tsx
# ==========================================================
$f=Get-Content $panel -Raw

# Measurement type
if($f -notmatch 'resolved_power_factor\?:number'){
  $f=$f.Replace(
    '  power_factor?:number;',
    '  power_factor?:number;'+[Environment]::NewLine+'  resolved_power_factor?:number;'+[Environment]::NewLine+'  power_factor_source?:string;'+[Environment]::NewLine+'  power_factor_penalized?:boolean;'
  )
}

# Invoice top-level derived flags
if($f -notmatch 'power_factor_penalized\?:boolean'){
  $f=$f.Replace(
    '  meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:Line[];',
    '  meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:Line[];power_factor_penalized?:boolean;resolved_power_factor?:number;power_factor_value_available?:boolean;power_factor_charge_amount?:number;'
  )
}

# Replace values()
$start=$f.IndexOf('function values(i:Invoice){')
$end=$f.IndexOf('function metricValue(', $start)
if($start -lt 0 -or $end -lt 0){throw "No encontré values()/metricValue en invoice-analysis-panel.tsx."}

$values=@'
function values(i:Invoice){
  const ms=i.invoice_measurements||[];
  const kwh=ms.reduce((s,m)=>s+Number(m.active_energy_kwh||0),0);
  const kvarh=ms.reduce((s,m)=>s+Number(m.reactive_energy_kvarh||0),0);
  const demand=Math.max(0,...ms.map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));
  const contracted=contractedBands(i).peak;
  const pfs=ms
    .map(m=>Number(m.resolved_power_factor||m.power_factor||0))
    .filter(v=>v>0);
  const pf=pfs.length?Math.min(...pfs):Number(i.resolved_power_factor||0);
  const surcharge=Math.max(0,...ms.map(m=>Number(m.reactive_surcharge_percent||0)));
  const cosCharge=(i.invoice_lines||[])
    .filter(x=>String(x.concept_code||"").toUpperCase()==="COS")
    .reduce((s,x)=>s+Math.max(0,Number(x.net_amount||0)),0);
  const penalized=Boolean(i.power_factor_penalized)||ms.some(m=>m.power_factor_penalized)||surcharge>0||cosCharge>0;
  const pfUnknownPenalized=penalized&&!(pf>0);
  return{kwh,kvarh,demand,contracted,pf,surcharge,penalized,pfUnknownPenalized,cosCharge};
}

'@
$f=$f.Substring(0,$start)+$values+$f.Substring($end)

# Add penalizedUnknown to InvoiceTrend data
$f=$f.Replace(
  '        contracted:values(invoice).contracted',
  '        contracted:values(invoice).contracted,'+[Environment]::NewLine+'        pfUnknownPenalized:values(invoice).pfUnknownPenalized,'+[Environment]::NewLine+'        penalized:values(invoice).penalized'
)

# Geometry uses 0.95 only as a visual marker for unknown penalized values.
$f=$f.Replace(
  '        const y=top+plotH-(d.value/max)*plotH;',
  '        const graphValue=metric==="pf"&&d.pfUnknownPenalized?0.95:d.value;'+[Environment]::NewLine+'        const y=top+plotH-(graphValue/max)*plotH;'
)

# Classify unknown penalty red
$oldClass='className={`invoice-analysis-bar${metric==="pf"&&d.value>0&&d.value<.95?" bad-pf":""}${metric==="pf"&&d.value>=.95?" good-pf":""}${selectedPeriod===d.period?" selected":""}`}'
$newClass='className={`invoice-analysis-bar${metric==="pf"&&((d.value>0&&d.value<.95)||d.pfUnknownPenalized)?" bad-pf":""}${metric==="pf"&&d.value>=.95&&!d.pfUnknownPenalized?" good-pf":""}${metric==="pf"&&d.pfUnknownPenalized?" pf-unknown-penalty":""}${selectedPeriod===d.period?" selected":""}`}'
if($f.Contains($oldClass)){$f=$f.Replace($oldClass,$newClass)}

# Tooltip
$f=$f.Replace(
  '<title>{labelPeriod(d.period)} · {fmt(metric,d.value)}</title>',
  '<title>{metric==="pf"&&d.pfUnknownPenalized?`${labelPeriod(d.period)} · Penalización de factor de potencia · cos φ no informado`: `${labelPeriod(d.period)} · ${fmt(metric,d.value)}`}</title>'
)

# KPI small text
$f=$f.Replace(
  '<small>{v.surcharge>0?`recargo ${v.surcharge}%`:"sin recargo detectado"}</small>',
  '<small>{v.surcharge>0?`recargo ${v.surcharge}%`:v.penalized?"penalización de factor de potencia facturada":"sin recargo detectado"}</small>'
)

Set-Content $panel $f -Encoding UTF8

# ==========================================================
# page.tsx
# ==========================================================
$p=Get-Content $page -Raw

if($p -notmatch 'resolved_power_factor\?:number'){
  $p=$p.Replace(
    'type Measurement = {active_energy_kwh?:number;reactive_energy_kvarh?:number;demand_kw?:number;power_factor?:number;',
    'type Measurement = {active_energy_kwh?:number;reactive_energy_kvarh?:number;demand_kw?:number;power_factor?:number;resolved_power_factor?:number;power_factor_source?:string;power_factor_penalized?:boolean;'
  )
}

if($p -notmatch 'power_factor_penalized\?:boolean'){
  $p=$p.Replace(
    'meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:InvoiceLine[]};',
    'meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:InvoiceLine[];power_factor_penalized?:boolean;resolved_power_factor?:number;power_factor_value_available?:boolean;power_factor_charge_amount?:number};'
  )
}

# Replace compact metrics function
$metricsStart=$p.IndexOf('function metrics(i:Invoice){')
$invoiceTableStart=$p.IndexOf('function InvoiceTable(', $metricsStart)
if($metricsStart -lt 0 -or $invoiceTableStart -lt 0){throw "No encontré metrics()/InvoiceTable en page.tsx."}

$metrics=@'
function metrics(i:Invoice){
  const ms=i.invoice_measurements||[];
  const kwh=ms.reduce((s,m)=>s+Number(m.active_energy_kwh||0),0);
  const demand=Math.max(0,...ms.map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));
  const contracted=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||Math.max(0,...(i.invoice_lines||[]).filter(x=>x.concept_code==="DEM"||x.concept_code==="DEP").map(x=>Number(x.quantity||0))));
  const pfs=ms.map(m=>Number(m.resolved_power_factor||m.power_factor||0)).filter(v=>v>0);
  const pf=pfs.length?Math.min(...pfs):Number(i.resolved_power_factor||0);
  const surcharge=Math.max(0,...ms.map(m=>Number(m.reactive_surcharge_percent||0)));
  const cosCharge=(i.invoice_lines||[]).filter(x=>String(x.concept_code||"").toUpperCase()==="COS").reduce((s,x)=>s+Math.max(0,Number(x.net_amount||0)),0);
  const penalized=Boolean(i.power_factor_penalized)||ms.some(m=>m.power_factor_penalized)||surcharge>0||cosCharge>0;
  return{kwh,demand,contracted,excess:Math.max(0,contracted-demand),pf,surcharge,penalized};
}

'@
$p=$p.Substring(0,$metricsStart)+$metrics+$p.Substring($invoiceTableStart)

# Table status when exact PF absent but penalty exists
$oldCell='{x.pf?<span className={`status-pill ${bad?"bad":"good"}`}>{x.pf.toFixed(3)} {bad?"Bajo":"Correcto"}</span>:<span className="status-pill neutral">No detectado</span>}'
$newCell='{x.pf?<span className={`status-pill ${bad?"bad":"good"}`}>{x.pf.toFixed(3)} {bad?"Bajo":"Correcto"}</span>:x.penalized?<span className="status-pill bad">Penalizado · FP S/D</span>:<span className="status-pill neutral">No detectado</span>}'
if($p.Contains($oldCell)){$p=$p.Replace($oldCell,$newCell)}

Set-Content $page $p -Encoding UTF8

# ==========================================================
# CSS
# ==========================================================
$c=Get-Content $css -Raw
if($c -notmatch 'EPEN POWER FACTOR V20'){
Add-Content $css @'

/* EPEN POWER FACTOR V20 */
.invoice-analysis-bar.pf-unknown-penalty rect{
  fill:#ef6a5b!important;
  fill-opacity:.34;
  stroke:#d94b3d;
  stroke-width:2;
  stroke-dasharray:5 4;
}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - Factor de potencia V20 aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Backend:" -ForegroundColor Yellow
Write-Host "  power_factor informado -> usa dato EPEN"
Write-Host "  sin FP + tangent_phi -> calcula cos(phi)"
Write-Host "  sin FP/tg + cargo COS -> marca penalizado sin inventar valor"
Write-Host ""
Write-Host "Ejemplo TIERRA MUNICIPALIDAD:"
Write-Host "  Junio 2026 -> 0,8461 rojo"
Write-Host "  Julio 2026 -> rojo punteado, FP S/D, porque existe COS"
Write-Host "  Agosto 2026 -> tg(phi)=1,43 => cos(phi) aprox. 0,573, rojo"
Write-Host ""
Write-Host "IMPORTANTE: desplegar BACKEND en Render y reiniciar/refrescar el front."
Write-Host "Backup: $backup"
