$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if (Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if (Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$path=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup="$path.bak-v10-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

$fmtStart=$text.IndexOf('function fmt(')
$panelStart=$text.IndexOf('export function InvoiceAnalysisPanel')

if($fmtStart -lt 0){throw "No encontré function fmt()."}
if($panelStart -lt 0){throw "No encontré InvoiceAnalysisPanel."}
if($panelStart -le $fmtStart){throw "El archivo está en un estado inesperado."}

$helpers=@'
function fmt(metric:Metric,value:number){
  if(metric==="amount")return money.format(value);
  if(metric==="demand")return `${nf.format(value)} kW`;
  if(metric==="pf")return value?value.toFixed(3):"S/D";
  return `${nf.format(value)} kWh`;
}

function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()]
      .sort((a,b)=>a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period,row])=>({
        period,
        row,
        value:Math.max(0,Number(row.monthly_saving||0))
      }));
  },[rows]);

  if(!data.length||!data.some(d=>d.value>0)){
    return <div className="invoice-tariff-no-data">
      <b>Sin ahorro tarifario valorizado</b>
      <span>No hay una simulación mensual disponible para este medidor.</span>
    </div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
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
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        return <g
          className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {d.row.current_tariff||"Actual"} → {d.row.recommended_tariff||"Propuesta"} · {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>
  </div>
}

function InvoiceTrend({rows,metric,selectedPeriod,onPeriod}:{rows:Invoice[];metric:Metric;selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,Invoice>();
    for(const row of rows){
      const p=periodOf(row);
      const current=map.get(p);
      if(!current||String(row.issue_date||row.id)>String(current.issue_date||current.id))map.set(p,row);
    }
    return [...map.entries()]
      .sort((a,b)=>a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period,invoice])=>({
        period,
        invoice,
        value:metricValue(invoice,metric),
        contracted:values(invoice).contracted
      }));
  },[rows,metric]);

  const width=1280,height=330,left=70,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(
    1,
    ...data.map(d=>d.value),
    ...(metric==="demand"?data.map(d=>d.contracted):[])
  )*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}>
          <line x1={left} x2={width-right} y1={y} y2={y}/>
          <text x={left-10} y={y+4} textAnchor="end">
            {metric==="pf"?(max*step).toFixed(2):nf.format(max*step)}
          </text>
        </g>
      })}

      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        return <g
          className={`invoice-analysis-bar${metric==="pf"&&d.value>0&&d.value<.95?" bad-pf":""}${metric==="pf"&&d.value>=.95?" good-pf":""}${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={y} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {fmt(metric,d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}

      {metric==="pf"&&<g className="invoice-pf-limit">
        <line x1={left} x2={width-right}
          y1={top+plotH-(0.95/max)*plotH}
          y2={top+plotH-(0.95/max)*plotH}/>
        <text x={width-right-4}
          y={top+plotH-(0.95/max)*plotH-7}
          textAnchor="end">Límite cos φ 0,95</text>
      </g>}

      {metric==="demand"&&data.map((d,index)=>d.contracted>0?
        <line
          key={`c-${d.period}`}
          className="invoice-contract-line"
          x1={left+index*slot}
          x2={left+(index+1)*slot}
          y1={top+plotH-(d.contracted/max)*plotH}
          y2={top+plotH-(d.contracted/max)*plotH}
        />:null)}
    </svg>

    {metric==="pf"&&<div className="invoice-pf-legend">
      <span><i className="good"/>Correcto: cos φ ≥ 0,95</span>
      <span><i className="bad"/>Revisar: cos φ &lt; 0,95</span>
    </div>}
  </div>
}

'@

# Reemplazar TODO entre function fmt y InvoiceAnalysisPanel.
# Esto elimina de una vez cualquier duplicado, fragmento huérfano o función rota.
$newText=$text.Substring(0,$fmtStart)+$helpers+$text.Substring($panelStart)

# Validaciones fuertes.
$tariffCount=([regex]::Matches($newText,'function TariffSavingTrend\(')).Count
$invoiceCount=([regex]::Matches($newText,'function InvoiceTrend\(')).Count
$fmtCount=([regex]::Matches($newText,'function fmt\(')).Count

if($tariffCount -ne 1){throw "TariffSavingTrend quedó definida $tariffCount veces."}
if($invoiceCount -ne 1){throw "InvoiceTrend quedó definida $invoiceCount veces."}
if($fmtCount -ne 1){throw "fmt quedó definida $fmtCount veces."}
if($newText -match '^\s*:\{rows:\{' ){throw "Todavía existe un fragmento huérfano al inicio de una línea."}

Set-Content $path $newText -Encoding UTF8

Write-Host ""
Write-Host "OK - bloque de helpers reconstruido completamente." -ForegroundColor Green
Write-Host "fmt: $fmtCount"
Write-Host "TariffSavingTrend: $tariffCount"
Write-Host "InvoiceTrend: $invoiceCount"
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Ahora ejecutá:" -ForegroundColor Yellow
Write-Host "  cd front"
Write-Host "  npm run dev"
