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

# ---------------- BACKEND ----------------
$main=Get-Content $mainPath -Raw

if($main -notmatch 'tariff_history'){
  if($main -match 'from \.routers import ([^\r\n]+)'){
    $current=$Matches[0]
    $new=$current.TrimEnd()+',tariff_history'
    $main=$main.Replace($current,$new)
  } else {
    throw "No encontré el import de routers en back\app\main.py."
  }

  $anchor='api.include_router(epen_optimization.router,prefix="/api")'
  if($main.Contains($anchor)){
    $main=$main.Replace($anchor,$anchor+"`r`n"+'api.include_router(tariff_history.router,prefix="/api")')
  } else {
    # si por alguna razón no está epen_optimization, lo agregamos después de analysis
    $anchor2='api.include_router(analysis.router,prefix="/api")'
    if(-not $main.Contains($anchor2)){throw "No encontré dónde registrar tariff_history en main.py."}
    $main=$main.Replace($anchor2,$anchor2+"`r`n"+'api.include_router(tariff_history.router,prefix="/api")')
  }

  Set-Content $mainPath $main -Encoding UTF8
}

# ---------------- FRONT ----------------
$inv=Get-Content $invoicePath -Raw

# React useEffect
if($inv -match 'import \{([^}]*)\} from "react";'){
  $whole=$Matches[0]
  $inside=$Matches[1]
  if($inside -notmatch '\buseEffect\b'){
    $newInside=($inside.Trim()+', useEffect')
    $inv=$inv.Replace($whole,'import {'+$newInside+'} from "react";')
  }
}

# Tipos avanzados
if($inv -notmatch 'type AdvancedTariffHistoryPoint'){
  $marker='type Metric='
  $idx=$inv.IndexOf($marker)
  if($idx -lt 0){throw "No encontré type Metric en invoice-analysis-panel.tsx."}
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
  $inv=$inv.Insert($idx,$typeBlock)
}

# Asegurar InvoiceTrend
if($inv -notmatch 'function InvoiceTrend\('){
  $marker='export function InvoiceAnalysisPanel'
  $idx=$inv.IndexOf($marker)
  if($idx -lt 0){throw "No encontré InvoiceAnalysisPanel."}
$invoiceTrend=@'
function InvoiceTrend({rows,metric,selectedPeriod,onPeriod}:{rows:Invoice[];metric:Metric;selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,Invoice>();
    for(const row of rows){
      const p=periodOf(row);
      const current=map.get(p);
      if(!current||String(row.issue_date||row.id)>String(current.issue_date||current.id))map.set(p,row);
    }
    return [...map.entries()].sort((a,b)=>a[0].localeCompare(b[0])).slice(-24).map(([period,invoice])=>({
      period,invoice,value:metricValue(invoice,metric),contracted:values(invoice).contracted
    }));
  },[rows,metric]);

  const width=1280,height=330,left=70,right=28,top=25,bottom=52,plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value),...(metric==="demand"?data.map(d=>d.contracted):[]))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  return <div className="invoice-analysis-chart-wrap"><svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
    {[0,.25,.5,.75,1].map(step=>{const y=top+plotH*(1-step);return <g key={step}><line x1={left} x2={width-right} y1={y} y2={y}/><text x={left-10} y={y+4} textAnchor="end">{metric==="pf"?(max*step).toFixed(2):nf.format(max*step)}</text></g>})}
    {data.map((d,index)=>{const x=left+index*slot+(slot-bw)/2,y=top+plotH-(d.value/max)*plotH;return <g className={`invoice-analysis-bar${metric==="pf"&&d.value>0&&d.value<.95?" bad-pf":""}${metric==="pf"&&d.value>=.95?" good-pf":""}${selectedPeriod===d.period?" selected":""}`} key={d.period} onClick={()=>onPeriod(d.period)}>
      <rect x={x} y={y} width={bw} height={Math.max(2,top+plotH-y)} rx="5"><title>{labelPeriod(d.period)} · {fmt(metric,d.value)}</title></rect>
      {(index%3===0||index===data.length-1)&&<text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
    </g>})}
    {metric==="pf"&&<g className="invoice-pf-limit"><line x1={left} x2={width-right} y1={top+plotH-(0.95/max)*plotH} y2={top+plotH-(0.95/max)*plotH}/><text x={width-right-4} y={top+plotH-(0.95/max)*plotH-7} textAnchor="end">Límite cos φ 0,95</text></g>}
    {metric==="demand"&&data.map((d,index)=>d.contracted>0?<line key={`c-${d.period}`} className="invoice-contract-line" x1={left+index*slot} x2={left+(index+1)*slot} y1={top+plotH-(d.contracted/max)*plotH} y2={top+plotH-(d.contracted/max)*plotH}/>:null)}
  </svg>{metric==="pf"&&<div className="invoice-pf-legend"><span><i className="good"/>Correcto: cos φ ≥ 0,95</span><span><i className="bad"/>Revisar: cos φ &lt; 0,95</span></div>}</div>
}

'@
  $inv=$inv.Insert($idx,$invoiceTrend)
}

# Reemplazar o insertar TariffSavingTrend antes de InvoiceTrend
$trendPattern='(?s)function TariffSavingTrend\(.*?(?=function InvoiceTrend\()'
$tariffTrend=@'
function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()].sort((a,b)=>a[0].localeCompare(b[0])).slice(-24).map(([period,row])=>({period,row,value:Math.max(0,Number(row.monthly_saving||0))}));
  },[rows]);

  if(!data.length||!data.some(d=>d.value>0)){
    return <div className="invoice-tariff-no-data"><b>Sin ahorro tarifario valorizado</b><span>No hay una simulación mensual disponible para este medidor.</span></div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52,plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);
  const axis=(value:number)=>value>=1000000?`$ ${(value/1000000).toLocaleString("es-AR",{maximumFractionDigits:1})} M`:value>=1000?`$ ${(value/1000).toLocaleString("es-AR",{maximumFractionDigits:0})} mil`:money.format(value);

  return <div className="invoice-analysis-chart-wrap"><svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
    {[0,.25,.5,.75,1].map(step=>{const y=top+plotH*(1-step);return <g key={step}><line x1={left} x2={width-right} y1={y} y2={y}/><text x={left-10} y={y+4} textAnchor="end">{axis(max*step)}</text></g>})}
    {data.map((d,index)=>{const x=left+index*slot+(slot-bw)/2,y=top+plotH-(d.value/max)*plotH;return <g className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}`} key={d.period} onClick={()=>onPeriod(d.period)}>
      <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5"><title>{labelPeriod(d.period)} · {d.row.current_tariff||"Actual"} → {d.row.recommended_tariff||"Propuesta"} · ahorro ${d.value.toLocaleString("es-AR")}</title></rect>
      {(index%3===0||index===data.length-1)&&<text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
    </g>})}
  </svg><div className="invoice-tariff-legend"><span><i/>Ahorro mensual con la tarifa propuesta</span></div></div>
}

'@

if([regex]::IsMatch($inv,$trendPattern)){
  $inv=[regex]::Replace($inv,$trendPattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $tariffTrend},1)
} else {
  $marker='function InvoiceTrend('
  $idx=$inv.IndexOf($marker)
  if($idx -lt 0){throw "No pude ubicar InvoiceTrend para insertar TariffSavingTrend."}
  $inv=$inv.Insert($idx,$tariffTrend)
}

# Estado advancedTariffHistory
$metricState='const[metric,setMetric]=useState<Metric>("kwh");'
if(-not $inv.Contains($metricState)){throw "No encontré el estado metric."}
if($inv -notmatch 'setAdvancedTariffHistory'){
  $inv=$inv.Replace($metricState,$metricState+"`r`n"+'  const[advancedTariffHistory,setAdvancedTariffHistory]=useState<AdvancedTariffHistoryResponse|null>(null);')
}

# Effect
if($inv -notmatch 'tariff-saving-history'){
  $marker='  async function saveMeterName(){'
  if(-not $inv.Contains($marker)){throw "No encontré saveMeterName para insertar useEffect."}
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
  $inv=$inv.Replace($marker,$effect+$marker)
}

# Reemplazar rama Ahorro tarifario de forma robusta
$startMarker='{metric==="tariff"?'
$start=$inv.IndexOf($startMarker)
if($start -lt 0){throw "No encontré la rama metric===tariff."}

$elseMarker=':<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>'
$elseIdx=$inv.IndexOf($elseMarker,$start)
if($elseIdx -lt 0){throw "No encontré la rama else de InvoiceTrend."}

$closeIdx=$elseIdx+$elseMarker.Length
if($closeIdx -ge $inv.Length -or $inv[$closeIdx] -ne '}'){
  # buscar el siguiente }
  $next=$inv.IndexOf('}',$closeIdx)
  if($next -lt 0){throw "No encontré el cierre de la rama tarifaria."}
  $closeIdx=$next
}
$closeIdx++

$newBranch=@'
{metric==="tariff"?(()=>{
          const legacyRows=tariffSavings.filter(x=>x.meter_id===selected.meter_id).map(x=>({
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

$inv=$inv.Substring(0,$start)+$newBranch+$inv.Substring($closeIdx)

Set-Content $invoicePath $inv -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
if($css -notmatch 'EPEN ADVANCED V7 FIX2'){
Add-Content $cssPath @'

/* EPEN ADVANCED V7 FIX2 */
.invoice-tariff-chart-view{position:relative}
.tariff-saving-bar rect{fill:#2b9b70}
.tariff-saving-bar.selected rect{fill:#116b49}
.invoice-tariff-legend{display:flex;justify-content:flex-end;padding:2px 26px 0;font-size:11px;color:#475569}
.invoice-tariff-legend span{display:flex;align-items:center;gap:7px}
.invoice-tariff-legend i{width:13px;height:13px;border-radius:4px;background:#2b9b70}
.invoice-tariff-selected-caption{position:absolute;right:26px;top:-2px;display:grid;text-align:right;pointer-events:none}
.invoice-tariff-selected-caption span{font-size:10px;color:#64748b}
.invoice-tariff-selected-caption b{font-size:14px;color:#047857}
.invoice-tariff-selected-caption small{font-size:9px;color:#94a3b8}
.invoice-tariff-no-data{height:330px;display:grid;place-content:center;text-align:center;gap:5px;color:#64748b}
.invoice-tariff-no-data b{font-size:15px;color:#334155}
.invoice-tariff-no-data span{font-size:11px}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - V7 FIX2 aplicada." -ForegroundColor Green
Write-Host "Este instalador ya no depende de que TariffSavingTrend e InvoiceTrend estén uno detrás del otro." -ForegroundColor Yellow
Write-Host "IMPORTANTE: reiniciá backend y front."
Write-Host "Backup: $backup"
