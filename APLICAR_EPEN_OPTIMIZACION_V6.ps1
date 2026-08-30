$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo=$null
if ((Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Root "front\app\globals.css"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Parent "front\app\globals.css"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$invoicePath=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$cssPath=Join-Path $Repo "front\app\globals.css"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $invoicePath $backup
Copy-Item $cssPath $backup

$inv=Get-Content $invoicePath -Raw

# Hacer que las barras tarifarias usen exactamente la misma clase/onda visual que Consumo/Demanda,
# sin tarjeta/resumen arriba: solo gráfico vertical + texto compacto del mes.
$start='function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:TariffSaving[];selectedPeriod:string;onPeriod:(p:string)=>void}){'
$end='export function InvoiceAnalysisPanel'
$startIndex=$inv.IndexOf($start)
$endIndex=$inv.IndexOf($end,$startIndex)
if($startIndex -lt 0 -or $endIndex -lt 0){throw "No encontré TariffSavingTrend de V5."}

$newTrend=@'
function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:TariffSaving[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,TariffSaving>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()].sort((a,b)=>a[0].localeCompare(b[0])).slice(-24).map(([period,row])=>({
      period,row,value:Math.max(0,Number(row.monthly_saving_with_vat||0))
    }));
  },[rows]);
  const width=1280,height=330,left=84,right=28,top=25,bottom=52,plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);
  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}><line x1={left} x2={width-right} y1={y} y2={y}/><text x={left-10} y={y+4} textAnchor="end">{money.format(max*step)}</text></g>
      })}
      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2,y=top+plotH-(d.value/max)*plotH;
        return <g className={`invoice-analysis-bar${selectedPeriod===d.period?" selected":""}`} key={d.period} onClick={()=>onPeriod(d.period)}>
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · ahorro tarifario {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&<text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>
  </div>
}

'@

$inv=$inv.Substring(0,$startIndex)+$newTrend+$inv.Substring($endIndex)

# Reemplazar vista tarifaria por una versión simple, estilo resto de métricas:
$start2='{metric==="tariff"?<div className="invoice-tariff-tab tariff-history-view">'
$endToken='</div>:<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}';
$s=$inv.IndexOf($start2)
$e=$inv.IndexOf($endToken,$s)
if($s -lt 0 -or $e -lt 0){throw "No encontré la vista tarifaria V5."}
$e += '</div>'.Length

$newView=@'
{metric==="tariff"?(()=>{
          const meterTariffRows=tariffSavings.filter(x=>x.meter_id===selected.meter_id);
          const selectedTariff=meterTariffRows.find(x=>String(x.billing_period).slice(0,7)===periodOf(selected));
          const selectedSaving=Number(selectedTariff?.monthly_saving_with_vat||0);
          return <div className="invoice-tariff-simple-view">
            <div className="invoice-tariff-simple-head">
              <div>
                <h4>Ahorro tarifario mensual</h4>
                <p>Cada barra muestra el ahorro que habría tenido esa factura con la tarifa propuesta.</p>
              </div>
              <div>
                <span>{periodOf(selected)}</span>
                <b>{money.format(selectedSaving)}</b>
                <small>{selectedTariff?.current_tariff||selected.current_tariff_code||"S/D"} → {selectedTariff?.recommended_tariff||"Sin cambio"}</small>
              </div>
            </div>
            <TariffSavingTrend rows={meterTariffRows} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>
          </div>;
        })():<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}
'@

$inv=$inv.Substring(0,$s)+$newView+$inv.Substring($e)
Set-Content $invoicePath $inv -Encoding UTF8

$css=Get-Content $cssPath -Raw
if($css -notmatch 'EPEN ADVANCED V6'){
Add-Content $cssPath @'

/* EPEN ADVANCED V6 */
.invoice-tariff-simple-view{padding:0}
.invoice-tariff-simple-head{display:flex;justify-content:space-between;align-items:flex-end;gap:20px;padding:0 4px 8px}
.invoice-tariff-simple-head h4{margin:0 0 3px;font-size:14px;color:#0f172a}
.invoice-tariff-simple-head p{margin:0;color:#64748b;font-size:11px}
.invoice-tariff-simple-head>div:last-child{display:grid;text-align:right}
.invoice-tariff-simple-head>div:last-child span{font-size:10px;color:#64748b;font-weight:800}
.invoice-tariff-simple-head>div:last-child b{font-size:18px;color:#047857}
.invoice-tariff-simple-head>div:last-child small{font-size:10px;color:#64748b}
@media(max-width:800px){.invoice-tariff-simple-head{align-items:flex-start;flex-direction:column}.invoice-tariff-simple-head>div:last-child{text-align:left}}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - EPEN Optimización V6 aplicada." -ForegroundColor Green
Write-Host "Ahorro tarifario ahora sigue la misma onda que Consumo/Demanda/Factor potencia:" -ForegroundColor Yellow
Write-Host "  - gráfico de barras verticales"
Write-Host "  - hasta 24 meses"
Write-Host "  - mes seleccionado resaltado"
Write-Host "  - tocar barra cambia de factura"
Write-Host "  - importe del ahorro mensual en eje Y"
Write-Host "Backup: $backup"
