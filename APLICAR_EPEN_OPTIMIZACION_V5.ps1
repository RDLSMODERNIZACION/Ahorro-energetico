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

# Ampliar TariffSaving con datos útiles si todavía está en formato mínimo
$oldType='type TariffSaving={meter_id:string;billing_period:string;monthly_saving_with_vat:number};'
$newType='type TariffSaving={meter_id:string;billing_period:string;current_tariff?:string;recommended_tariff?:string;current_cost_with_vat?:number;recommended_cost_with_vat?:number;monthly_saving_with_vat:number;annual_saving_with_vat?:number};'
if($inv.Contains($oldType)){$inv=$inv.Replace($oldType,$newType)}

# Insertar componente gráfico histórico de ahorro tarifario
if($inv -notmatch 'function TariffSavingTrend'){
$marker='function InvoiceTrend({rows,metric,selectedPeriod,onPeriod}:{rows:Invoice[];metric:Metric;selectedPeriod:string;onPeriod:(p:string)=>void}){'
$idx=$inv.IndexOf($marker)
if($idx -lt 0){throw "No encontré InvoiceTrend."}

$component=@'
function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:TariffSaving[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,TariffSaving>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(!p)continue;
      map.set(p,row);
    }
    return [...map.entries()].sort((a,b)=>a[0].localeCompare(b[0])).slice(-24).map(([period,row])=>({
      period,
      row,
      value:Math.max(0,Number(row.monthly_saving_with_vat||0))
    }));
  },[rows]);
  const width=1280,height=330,left=84,right=28,top=28,bottom=54,plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.10;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);
  return <div className="invoice-analysis-chart-wrap tariff-saving-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart tariff-saving-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}><line x1={left} x2={width-right} y1={y} y2={y}/><text x={left-10} y={y+4} textAnchor="end">{money.format(max*step)}</text></g>
      })}
      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        return <g className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}${d.value<=0?" zero":""}`} key={d.period} onClick={()=>onPeriod(d.period)}>
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · ahorro {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&<text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>
  </div>
}

'@
$inv=$inv.Insert($idx,$component)
}

# Reemplazar contenido de metric==="tariff" por una vista histórica centrada en ahorro mensual
$start='{metric==="tariff"?<div className="invoice-tariff-tab">'
$startIndex=$inv.IndexOf($start)
if($startIndex -lt 0){throw "No encontré la pestaña Ahorro tarifario V4."}

# Buscar el cierre exacto previo a :<InvoiceTrend
$endToken='</div>:<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}';
$endIndex=$inv.IndexOf($endToken,$startIndex)
if($endIndex -lt 0){throw "No encontré el cierre de la pestaña tarifaria V4."}
$endIndex += '</div>'.Length

$newView=@'
{metric==="tariff"?<div className="invoice-tariff-tab tariff-history-view">
          {(()=>{
            const meterTariffRows=tariffSavings.filter(x=>x.meter_id===selected.meter_id);
            const selectedTariff=meterTariffRows.find(x=>String(x.billing_period).slice(0,7)===periodOf(selected));
            const selectedSaving=Number(selectedTariff?.monthly_saving_with_vat||0);
            const currentCost=Number(selectedTariff?.current_cost_with_vat||0);
            const proposedCost=Number(selectedTariff?.recommended_cost_with_vat||0);
            const currentTariff=selectedTariff?.current_tariff||selected.current_tariff_code||"S/D";
            const proposedTariff=selectedTariff?.recommended_tariff||"Sin cambio propuesto";
            return <>
              <div className="invoice-tariff-history-head">
                <div>
                  <span>AHORRO TARIFARIO DEL MES SELECCIONADO</span>
                  <b>{money.format(selectedSaving)}</b>
                  <small>{periodOf(selected)} · {currentTariff} → {proposedTariff}</small>
                </div>
                <div>
                  <span>FACTURA ACTUAL SIMULADA</span>
                  <b>{currentCost>0?money.format(currentCost):"S/D"}</b>
                  <small>{currentTariff}</small>
                </div>
                <div className="proposed">
                  <span>FACTURA CON TARIFA PROPUESTA</span>
                  <b>{proposedCost>0?money.format(proposedCost):"S/D"}</b>
                  <small>{proposedTariff}</small>
                </div>
              </div>

              <div className="invoice-tariff-history-title">
                <div><h4>Ahorro mensual histórico por cambio de tarifa</h4><p>Cada barra muestra cuánto se habría ahorrado en ese mes aplicando la categoría tarifaria recomendada para ese período.</p></div>
                <strong>{selectedSaving>0?money.format(selectedSaving):"Sin ahorro"}<small>mes seleccionado</small></strong>
              </div>

              <TariffSavingTrend rows={meterTariffRows} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>

              <div className="invoice-tariff-history-foot">
                <div><span>Tarifa actual</span><b>{currentTariff}</b></div>
                <div><span>Tarifa propuesta</span><b>{proposedTariff}</b></div>
                <div><span>Ahorro mensual</span><b>{money.format(selectedSaving)}</b></div>
                <div><span>Ahorro anualizado</span><b>{money.format(selectedSaving*12)}</b></div>
              </div>

              {!selectedTariff&&<div className="invoice-tariff-empty">No hay simulación de cambio tarifario valorizada para esta factura/período.</div>}
            </>;
          })()}
        </div>
'@

$inv=$inv.Substring(0,$startIndex)+$newView+$inv.Substring($endIndex)
Set-Content $invoicePath $inv -Encoding UTF8

$css=Get-Content $cssPath -Raw
if($css -notmatch 'EPEN ADVANCED V5'){
$styles=@'

/* EPEN ADVANCED V5 */
.tariff-history-view{padding:18px 22px 24px}
.invoice-tariff-history-head{display:grid;grid-template-columns:1.2fr 1fr 1fr;gap:12px;margin-bottom:18px}
.invoice-tariff-history-head>div{display:grid;gap:4px;padding:14px 16px;border:1px solid #e2e8f0;border-radius:12px;background:#f8fafc}
.invoice-tariff-history-head>div:first-child{background:#ecfdf5;border-color:#a7f3d0}
.invoice-tariff-history-head>div.proposed{background:#f0fdf4;border-color:#bbf7d0}
.invoice-tariff-history-head span{font-size:10px;font-weight:900;letter-spacing:.07em;color:#64748b}
.invoice-tariff-history-head b{font-size:20px;color:#0f172a}
.invoice-tariff-history-head>div:first-child b,.invoice-tariff-history-head>div.proposed b{color:#047857}
.invoice-tariff-history-head small{font-size:11px;color:#64748b}
.invoice-tariff-history-title{display:flex;align-items:flex-end;justify-content:space-between;gap:20px;margin:0 2px 8px}
.invoice-tariff-history-title h4{margin:0 0 3px;font-size:15px;color:#0f172a}
.invoice-tariff-history-title p{margin:0;color:#64748b;font-size:11px}
.invoice-tariff-history-title strong{display:grid;text-align:right;color:#047857;font-size:18px}
.invoice-tariff-history-title strong small{font-size:10px;color:#94a3b8;font-weight:600}
.tariff-saving-chart-wrap{margin-top:2px}
.tariff-saving-chart .tariff-saving-bar rect{fill:#10b981}
.tariff-saving-chart .tariff-saving-bar.selected rect{fill:#047857}
.tariff-saving-chart .tariff-saving-bar.zero rect{fill:#cbd5e1}
.invoice-tariff-history-foot{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:10px}
.invoice-tariff-history-foot>div{display:grid;gap:3px;padding:10px 12px;border-radius:10px;background:#f8fafc;border:1px solid #e2e8f0}
.invoice-tariff-history-foot span{font-size:10px;color:#64748b;font-weight:800}
.invoice-tariff-history-foot b{font-size:13px;color:#0f172a}
.invoice-tariff-history-foot>div:nth-child(3) b,.invoice-tariff-history-foot>div:nth-child(4) b{color:#047857}
@media(max-width:1050px){.invoice-tariff-history-head{grid-template-columns:1fr}.invoice-tariff-history-foot{grid-template-columns:repeat(2,minmax(0,1fr))}}
'@
Add-Content $cssPath $styles -Encoding UTF8
}

Write-Host ""
Write-Host "OK - EPEN Optimización V5 aplicada." -ForegroundColor Green
Write-Host "La pestaña Ahorro tarifario ahora muestra:" -ForegroundColor Yellow
Write-Host "  - ahorro real simulado de CADA MES"
Write-Host "  - factura actual simulada"
Write-Host "  - factura con tarifa propuesta"
Write-Host "  - gráfico histórico de hasta 24 meses"
Write-Host "  - al tocar una barra cambia al período seleccionado"
Write-Host "Backup: $backup"
