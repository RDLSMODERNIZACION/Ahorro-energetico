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
$backup="$path.bak-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

if($text -match 'function InvoiceTrend\('){
  Write-Host "InvoiceTrend ya existe. No hice cambios." -ForegroundColor Yellow
  exit 0
}

$marker='function TariffSavingTrend('
$idx=$text.IndexOf($marker)
if($idx -lt 0){
  $marker='export function InvoiceAnalysisPanel'
  $idx=$text.IndexOf($marker)
}
if($idx -lt 0){throw "No encontré dónde reinsertar InvoiceTrend."}

$fn=@'
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

$text=$text.Insert($idx,$fn)
Set-Content $path $text -Encoding UTF8

Write-Host "OK - InvoiceTrend restaurado." -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Ahora ejecutá:" -ForegroundColor Yellow
Write-Host "  cd front"
Write-Host "  npm run dev"
