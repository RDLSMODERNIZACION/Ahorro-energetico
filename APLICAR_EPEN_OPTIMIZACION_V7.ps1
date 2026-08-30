$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if ((Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Root "back\app\main.py"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Parent "back\app\main.py"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$invoicePath=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$mainPath=Join-Path $Repo "back\app\main.py"
$cssPath=Join-Path $Repo "front\app\globals.css"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $invoicePath $backup
Copy-Item $mainPath $backup
Copy-Item $cssPath $backup

Copy-Item (Join-Path $Root "payload\back\app\routers\tariff_history.py") (Join-Path $Repo "back\app\routers\tariff_history.py") -Force

# --------------------------------------------------------------------
# Backend main.py
# --------------------------------------------------------------------
$main=Get-Content $mainPath -Raw
if($main -notmatch 'tariff_history'){
  $main=$main.Replace(
    'from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization',
    'from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization,tariff_history'
  )
  if($main -notmatch 'tariff_history' -and $main -match 'from \.routers import'){
    throw "No pude agregar tariff_history al import de main.py."
  }
  $needle='api.include_router(epen_optimization.router,prefix="/api")'
  if(-not $main.Contains($needle)){throw "No encontré el router epen_optimization en main.py. Aplicá primero V1."}
  $main=$main.Replace($needle,$needle+"`r`n"+'api.include_router(tariff_history.router,prefix="/api")')
  Set-Content $mainPath $main -Encoding UTF8
}

# --------------------------------------------------------------------
# Front invoice-analysis-panel.tsx
# --------------------------------------------------------------------
$inv=Get-Content $invoicePath -Raw

# useEffect
$inv=$inv.Replace(
  'import { useMemo, useState } from "react";',
  'import { useEffect, useMemo, useState } from "react";'
)

# Tipos del histórico
if($inv -notmatch 'type AdvancedTariffHistoryPoint'){
$typeBlock=@'
type AdvancedTariffHistoryPoint={
  billing_period:string;
  current_tariff:string;
  recommended_tariff:string;
  current_cost:number;
  recommended_cost:number;
  monthly_saving:number;
  annualized_saving:number;
  capacity_kw:number;
};
type AdvancedTariffHistoryResponse={
  meter_id:string;
  mode:"t4"|"none";
  current_tariff?:string;
  recommended_tariff?:string;
  taxes_included?:boolean;
  points:AdvancedTariffHistoryPoint[];
};

'@
  $marker='type Metric='
  $idx=$inv.IndexOf($marker)
  if($idx -lt 0){throw "No encontré type Metric."}
  $inv=$inv.Insert($idx,$typeBlock)
}

# TariffSavingTrend acepta un shape simple y se ve IGUAL que InvoiceTrend.
$start='function TariffSavingTrend('
$end='function InvoiceTrend('
$s=$inv.IndexOf($start)
$e=$inv.IndexOf($end,$s)
if($s -lt 0 -or $e -lt 0){throw "No encontré TariffSavingTrend/InvoiceTrend."}

$newTrend=@'
function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()].sort((a,b)=>a[0].localeCompare(b[0])).slice(-24).map(([period,row])=>({
      period,row,value:Math.max(0,Number(row.monthly_saving||0))
    }));
  },[rows]);

  if(!data.length||!data.some(d=>d.value>0)){
    return <div className="invoice-tariff-no-data">
      <b>Sin ahorro tarifario valorizado</b>
      <span>No hay una simulación mensual disponible para este medidor/período.</span>
    </div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52,plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  const axis=(value:number)=>{
    if(value>=1000000)return `$ ${(value/1000000).toLocaleString("es-AR",{maximumFractionDigits:1})} M`;
    if(value>=1000)return `$ ${(value/1000).toLocaleString("es-AR",{maximumFractionDigits:0})} mil`;
    return money.format(value);
  };

  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}>
          <line x1={left} x2={width-right} y1={y} y2={y}/>
          <text x={left-10} y={y+4} textAnchor="end">{axis(max*step)}</text>
        </g>
      })}
      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2,y=top+plotH-(d.value/max)*plotH;
        return <g className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}`} key={d.period} onClick={()=>onPeriod(d.period)}>
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {d.row.current_tariff||"Actual"} → {d.row.recommended_tariff||"Propuesta"} · ahorro {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&<text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>
    <div className="invoice-tariff-legend">
      <span><i/>Ahorro mensual con la tarifa propuesta</span>
    </div>
  </div>
}

'@
$inv=$inv.Substring(0,$s)+$newTrend+$inv.Substring($e)

# Estado + fetch dentro de InvoiceAnalysisPanel
$stateNeedle='const[metric,setMetric]=useState<Metric>("kwh");'
if(-not $inv.Contains($stateNeedle)){throw "No encontré el estado metric."}
if($inv -notmatch 'advancedTariffHistory'){
  $replacement=$stateNeedle+"`r`n"+'  const[advancedTariffHistory,setAdvancedTariffHistory]=useState<AdvancedTariffHistoryResponse|null>(null);'
  $inv=$inv.Replace($stateNeedle,$replacement)
}

# Insertar useEffect luego de selected/m variables, de forma segura antes de saveMeterName
$saveMarker='  async function saveMeterName(){'
if(-not $inv.Contains($saveMarker)){throw "No encontré saveMeterName."}
if($inv -notmatch 'tariff-saving-history'){
$effect=@'
  useEffect(()=>{
    let cancelled=false;
    async function loadTariffHistory(){
      try{
        const{data}=await supabase.auth.getSession();
        if(!data.session||!selected.meter_id)return;
        const response=await fetch(`${API}/api/meters/${selected.meter_id}/tariff-saving-history`,{
          cache:"no-store",
          headers:{Authorization:`Bearer ${data.session.access_token}`}
        });
        if(!response.ok)throw new Error(await response.text());
        const json=await response.json() as AdvancedTariffHistoryResponse;
        if(!cancelled)setAdvancedTariffHistory(json);
      }catch{
        if(!cancelled)setAdvancedTariffHistory(null);
      }
    }
    loadTariffHistory();
    return()=>{cancelled=true};
  },[selected.meter_id]);

'@
$inv=$inv.Replace($saveMarker,$effect+$saveMarker)
}

# Reemplazar vista simple actual por una que prioriza el histórico T4.
$start2='{metric==="tariff"?(()=>{'
$s2=$inv.IndexOf($start2)
$endToken='})():<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}';
$e2=$inv.IndexOf($endToken,$s2)
if($s2 -lt 0 -or $e2 -lt 0){throw "No encontré la vista de Ahorro tarifario actual."}
$e2 += $endToken.Length

$newView=@'
{metric==="tariff"?(()=>{
          const legacyRows=tariffSavings
            .filter(x=>x.meter_id===selected.meter_id)
            .map(x=>({
              billing_period:String(x.billing_period).slice(0,7),
              monthly_saving:Number(x.monthly_saving_with_vat||0),
              current_tariff:x.current_tariff,
              recommended_tariff:x.recommended_tariff
            }));
          const advancedRows=(advancedTariffHistory?.points||[]).map(x=>({
            billing_period:String(x.billing_period).slice(0,7),
            monthly_saving:Number(x.monthly_saving||0),
            current_tariff:x.current_tariff,
            recommended_tariff:x.recommended_tariff
          }));
          const chartRows=advancedRows.some(x=>x.monthly_saving>0)?advancedRows:legacyRows;
          const selectedRow=chartRows.find(x=>x.billing_period===periodOf(selected));
          return <div className="invoice-tariff-chart-view">
            <TariffSavingTrend rows={chartRows} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>
            {selectedRow&&<div className="invoice-tariff-selected-caption">
              <span>{selectedRow.current_tariff||selected.current_tariff_code||"Actual"} → {selectedRow.recommended_tariff||"Propuesta"}</span>
              <b>{money.format(Number(selectedRow.monthly_saving||0))} de ahorro en {periodOf(selected)}</b>
              {advancedRows.some(x=>x.monthly_saving>0)&&<small>Simulación antes de impuestos · T4 requiere contrato EPEN</small>}
            </div>}
          </div>;
        })():<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}
'@
$inv=$inv.Substring(0,$s2)+$newView+$inv.Substring($e2)

Set-Content $invoicePath $inv -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
if($css -notmatch 'EPEN ADVANCED V7'){
Add-Content $cssPath @'

/* EPEN ADVANCED V7 */
.invoice-tariff-chart-view{position:relative}
.tariff-saving-bar rect{fill:#2b9b70}
.tariff-saving-bar.selected rect{fill:#116b49}
.invoice-tariff-legend{display:flex;justify-content:flex-end;padding:2px 26px 0;font-size:11px;color:#475569}
.invoice-tariff-legend span{display:flex;align-items:center;gap:7px}
.invoice-tariff-legend i{width:13px;height:13px;border-radius:4px;background:#2b9b70}
.invoice-tariff-selected-caption{position:absolute;right:26px;top:-3px;display:grid;text-align:right;pointer-events:none}
.invoice-tariff-selected-caption span{font-size:10px;color:#64748b}
.invoice-tariff-selected-caption b{font-size:14px;color:#047857}
.invoice-tariff-selected-caption small{font-size:9px;color:#94a3b8}
.invoice-tariff-no-data{height:330px;display:grid;place-content:center;text-align:center;gap:5px;color:#64748b}
.invoice-tariff-no-data b{font-size:15px;color:#334155}
.invoice-tariff-no-data span{font-size:11px}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - EPEN Optimización V7 aplicada." -ForegroundColor Green
Write-Host "Ahora Ahorro tarifario:" -ForegroundColor Yellow
Write-Host "  - usa barras verticales iguales a Factor de potencia"
Write-Host "  - para T3A-MT candidato, grafica T3A -> T4-MT mes a mes"
Write-Host "  - no muestra escala $0/$1 cuando no hay datos"
Write-Host "  - muestra hasta 24 meses"
Write-Host "  - tocar una barra selecciona ese mes"
Write-Host ""
Write-Host "IMPORTANTE: reiniciá BACKEND y FRONT porque se agregó un endpoint nuevo."
Write-Host "Backup: $backup"
