$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if ((Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Root "back\app\routers\tariff_history.py"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Parent "back\app\routers\tariff_history.py"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$front=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$backend=Join-Path $Repo "back\app\routers\tariff_history.py"
$css=Join-Path $Repo "front\app\globals.css"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_v13_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $front $backup
Copy-Item $backend $backup
Copy-Item $css $backup

Copy-Item (Join-Path $Root "payload\back\app\routers\tariff_history.py") $backend -Force

$text=Get-Content $front -Raw

# Ampliar tipo AdvancedTariffHistoryPoint
if($text -match 'type AdvancedTariffHistoryPoint=\{'){
  if($text -notmatch 'proposed_components\?:'){
    $pattern='(type AdvancedTariffHistoryPoint=\{[\s\S]*?capacity_kw:number;)'
    $replacement=@'
$1
  available?:boolean;
  reason?:string|null;
  resolution_number?:string|null;
  billing_month?:string|null;
  consumption_month?:string|null;
  current_cost_source?:string;
  current_components?:Array<{code:string;description?:string;quantity?:number|null;unit_price?:number|null;net_amount:number}>;
  proposed_components?:Array<{code:string;description?:string;quantity?:number|null;unit_price?:number|null;net_amount:number}>;
'@
    $text=[regex]::Replace($text,$pattern,$replacement,1)
  }
}

# Reemplazar la rama completa Ahorro tarifario por una versión con detalle debajo.
$start=$text.IndexOf('{metric==="tariff" ? (() => {')
if($start -lt 0){$start=$text.IndexOf('{metric==="tariff"?(()=>{')}
if($start -lt 0){throw "No encontré la rama Ahorro tarifario."}

$elseMarker=': ('+[Environment]::NewLine+'          <InvoiceTrend'
$elseIdx=$text.IndexOf($elseMarker,$start)
if($elseIdx -lt 0){
  $elseMarker=':<InvoiceTrend'
  $elseIdx=$text.IndexOf($elseMarker,$start)
}
if($elseIdx -lt 0){throw "No encontré el else de InvoiceTrend."}

# Encontrar el cierre del ternario después de InvoiceTrend.
$closeMarker=')}' 
$closeIdx=$text.IndexOf($closeMarker,$elseIdx)
if($closeIdx -lt 0){
  $closeMarker='/>}'
  $closeIdx=$text.IndexOf($closeMarker,$elseIdx)
}
if($closeIdx -lt 0){throw "No encontré el cierre del ternario."}
$closeIdx += $closeMarker.Length

$newBranch=@'
{metric==="tariff" ? (() => {
          const legacyRows=tariffSavings
            .filter(x=>x.meter_id===selected.meter_id)
            .map(x=>({
              billing_period:String(x.billing_period).slice(0,7),
              monthly_saving:Number(x.monthly_saving_with_vat||0),
              current_tariff:x.current_tariff,
              recommended_tariff:x.recommended_tariff,
              available:true
            }));

          const advancedRows=(advancedTariffHistory?.points||[]).map(x=>({
            billing_period:String(x.billing_period).slice(0,7),
            monthly_saving:Number(x.monthly_saving||0),
            current_tariff:x.current_tariff,
            recommended_tariff:x.recommended_tariff,
            available:x.available!==false
          }));

          const chartRows=advancedRows.length?advancedRows:legacyRows;
          const detail=advancedTariffHistory?.points.find(x=>String(x.billing_period).slice(0,7)===periodOf(selected));

          return <div className="invoice-tariff-detail-view">
            <TariffSavingTrend
              rows={chartRows}
              selectedPeriod={periodOf(selected)}
              onPeriod={setSelectedPeriod}
            />

            <div className="invoice-tariff-period-detail">
              <div className="invoice-tariff-period-head">
                <div>
                  <span>DETALLE DEL PERÍODO</span>
                  <h4>{periodOf(selected)} · {detail?.current_tariff||selected.current_tariff_code||"Actual"} → {detail?.recommended_tariff||"T4"}</h4>
                  <p>{detail?.available===false?"No se puede valorizar este mes porque falta el cuadro oficial T4 correspondiente.":"Comparación entre lo realmente facturado y la tarifa T4 simulada del mismo período."}</p>
                </div>
                <div className={detail?.available===false?"missing":"saving"}>
                  <span>AHORRO TARIFARIO</span>
                  <b>{detail?.available===false?"S/D":money.format(Number(detail?.monthly_saving||0))}</b>
                  <small>{detail?.available===false?"Falta cuadro tarifario":`${money.format(Number(detail?.annualized_saving||0))} anualizado`}</small>
                </div>
              </div>

              {detail?.available!==false&&detail&&<>
                <div className="invoice-tariff-summary-grid">
                  <article>
                    <span>TARIFA ACTUAL REAL</span>
                    <b>{money.format(Number(detail.current_cost||0))}</b>
                    <small>Subtotal real tomado de invoice_lines</small>
                  </article>
                  <article>
                    <span>T4 SIMULADA</span>
                    <b>{money.format(Number(detail.recommended_cost||0))}</b>
                    <small>{detail.recommended_tariff} · {nf.format(Number(detail.capacity_kw||0))} kW</small>
                  </article>
                  <article>
                    <span>CUADRO OFICIAL APLICADO</span>
                    <b>{detail.resolution_number||"S/D"}</b>
                    <small>Facturación {String(detail.billing_month||periodOf(selected)).slice(0,7)} · Consumo {String(detail.consumption_month||"S/D").slice(0,7)}</small>
                  </article>
                </div>

                <div className="invoice-tariff-comparison-grid">
                  <div>
                    <h5>{detail.current_tariff} real facturada</h5>
                    <table>
                      <thead><tr><th>Concepto</th><th>Cantidad</th><th>Precio</th><th>Importe</th></tr></thead>
                      <tbody>{(detail.current_components||[]).map((row,index)=><tr key={`${row.code}-${index}`}>
                        <td><b>{row.code}</b><small>{row.description||""}</small></td>
                        <td>{row.quantity==null?"—":dec.format(Number(row.quantity))}</td>
                        <td>{row.unit_price==null?"—":money.format(Number(row.unit_price))}</td>
                        <td><b>{money.format(Number(row.net_amount||0))}</b></td>
                      </tr>)}</tbody>
                    </table>
                  </div>

                  <div>
                    <h5>{detail.recommended_tariff} simulada</h5>
                    <table>
                      <thead><tr><th>Concepto</th><th>Cantidad</th><th>Precio oficial</th><th>Importe</th></tr></thead>
                      <tbody>{(detail.proposed_components||[]).map((row,index)=><tr key={`${row.code}-${index}`}>
                        <td><b>{row.code}</b><small>{row.description||""}</small></td>
                        <td>{row.quantity==null?"—":dec.format(Number(row.quantity))}</td>
                        <td>{row.unit_price==null?"—":money.format(Number(row.unit_price))}</td>
                        <td><b>{money.format(Number(row.net_amount||0))}</b></td>
                      </tr>)}</tbody>
                    </table>
                  </div>
                </div>

                <div className="invoice-tariff-formula">
                  <span>FÓRMULA DEL AHORRO</span>
                  <b>{money.format(Number(detail.current_cost||0))} − {money.format(Number(detail.recommended_cost||0))} = {money.format(Number(detail.monthly_saving||0))}</b>
                  <small>Actual real facturada − T4 simulada · antes de impuestos</small>
                </div>
              </>}

              {detail?.available===false&&<div className="invoice-tariff-missing-detail">
                <b>Falta el cuadro oficial {detail.recommended_tariff} para {periodOf(selected)}</b>
                <span>La factura actual sí está cargada. No se extrapola el precio de otro mes: el ahorro queda sin valorizar hasta incorporar el cuadro tarifario oficial correspondiente.</span>
              </div>}
            </div>
          </div>;
        })() : (
          <InvoiceTrend
            rows={sorted}
            metric={metric}
            selectedPeriod={periodOf(selected)}
            onPeriod={setSelectedPeriod}
          />
        )}
'@

$text=$text.Substring(0,$start)+$newBranch+$text.Substring($closeIdx)
Set-Content $front $text -Encoding UTF8

$c=Get-Content $css -Raw
if($c -notmatch 'EPEN DETAIL V13'){
Add-Content $css @'

/* EPEN DETAIL V13 */
.invoice-tariff-detail-view{display:grid;gap:16px}
.invoice-tariff-period-detail{border-top:1px solid #e2e8f0;padding:18px 22px 22px;background:#fbfdfc}
.invoice-tariff-period-head{display:flex;justify-content:space-between;align-items:flex-start;gap:20px;margin-bottom:14px}
.invoice-tariff-period-head>div:first-child span{font-size:9px;font-weight:900;letter-spacing:.08em;color:#64748b}
.invoice-tariff-period-head h4{margin:3px 0;font-size:17px;color:#0f172a}
.invoice-tariff-period-head p{margin:0;font-size:11px;color:#64748b}
.invoice-tariff-period-head>div:last-child{min-width:220px;display:grid;text-align:right;padding:10px 12px;border-radius:10px}
.invoice-tariff-period-head>div:last-child.saving{background:#ecfdf5;border:1px solid #a7f3d0}
.invoice-tariff-period-head>div:last-child.missing{background:#f8fafc;border:1px solid #cbd5e1}
.invoice-tariff-period-head>div:last-child span{font-size:9px;font-weight:900;color:#64748b}
.invoice-tariff-period-head>div:last-child b{font-size:21px;color:#047857}
.invoice-tariff-period-head>div:last-child.missing b{color:#64748b}
.invoice-tariff-period-head>div:last-child small{font-size:10px;color:#64748b}

.invoice-tariff-summary-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-bottom:14px}
.invoice-tariff-summary-grid article{display:grid;gap:4px;padding:12px 14px;border:1px solid #e2e8f0;border-radius:11px;background:#fff}
.invoice-tariff-summary-grid span{font-size:9px;font-weight:900;color:#64748b}
.invoice-tariff-summary-grid b{font-size:16px;color:#0f172a}
.invoice-tariff-summary-grid small{font-size:10px;color:#64748b}

.invoice-tariff-comparison-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.invoice-tariff-comparison-grid>div{border:1px solid #e2e8f0;border-radius:12px;background:#fff;overflow:hidden}
.invoice-tariff-comparison-grid h5{margin:0;padding:11px 13px;background:#f8fafc;border-bottom:1px solid #e2e8f0;font-size:12px;color:#0f172a}
.invoice-tariff-comparison-grid table{width:100%;border-collapse:collapse;font-size:10px}
.invoice-tariff-comparison-grid th,.invoice-tariff-comparison-grid td{padding:8px 10px;border-bottom:1px solid #edf2f7;text-align:right}
.invoice-tariff-comparison-grid th:first-child,.invoice-tariff-comparison-grid td:first-child{text-align:left}
.invoice-tariff-comparison-grid td:first-child{display:grid;gap:1px}
.invoice-tariff-comparison-grid td small{font-size:8px;color:#94a3b8}
.invoice-tariff-comparison-grid td b{color:#0f172a}

.invoice-tariff-formula{display:grid;gap:3px;margin-top:12px;padding:12px 14px;border-radius:11px;background:#ecfdf5;border:1px solid #a7f3d0}
.invoice-tariff-formula span{font-size:9px;font-weight:900;color:#047857}
.invoice-tariff-formula b{font-size:16px;color:#065f46}
.invoice-tariff-formula small{font-size:10px;color:#64748b}
.invoice-tariff-missing-detail{display:grid;gap:5px;padding:16px;border-radius:11px;background:#f8fafc;border:1px dashed #94a3b8}
.invoice-tariff-missing-detail b{font-size:13px;color:#475569}
.invoice-tariff-missing-detail span{font-size:11px;color:#64748b}
@media(max-width:1000px){
  .invoice-tariff-summary-grid,.invoice-tariff-comparison-grid{grid-template-columns:1fr}
  .invoice-tariff-period-head{flex-direction:column}
  .invoice-tariff-period-head>div:last-child{width:100%;text-align:left}
}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - V13 aplicada." -ForegroundColor Green
Write-Host "Al tocar un mes en Ahorro tarifario ahora se muestra:" -ForegroundColor Yellow
Write-Host "  - costo T3/T3A real"
Write-Host "  - costo T4 simulado"
Write-Host "  - resolución EPEN aplicada"
Write-Host "  - DEM/ECO y precios unitarios"
Write-Host "  - detalle de conceptos reales de factura"
Write-Host "  - fórmula exacta del ahorro"
Write-Host "  - aviso si falta cuadro oficial"
Write-Host ""
Write-Host "IMPORTANTE: desplegar backend en Render."
Write-Host "Backup: $backup"
