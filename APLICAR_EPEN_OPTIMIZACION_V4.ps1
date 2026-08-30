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

# ---------------------------------------------------------
# 1. Agregar "tariff" como pestaña del gráfico
# ---------------------------------------------------------
$inv=$inv.Replace('type Metric="kwh"|"amount"|"demand"|"pf";','type Metric="kwh"|"amount"|"demand"|"pf"|"tariff";')

# ---------------------------------------------------------
# 2. Quitar el cuadro superior ANÁLISIS TARIFARIO AVANZADO EPEN
# ---------------------------------------------------------
$start='      {optimization&&(isT3||optimization.t4.status==="candidate"||(currentVoltage==="BT"&&["strong","candidate","preliminary"].includes(optimization.mt.status)))&&<section className="invoice-analysis-panel epen-individual-analysis">'
$end='      </section>}'
$startIndex=$inv.IndexOf($start)
if($startIndex -ge 0){
  $endIndex=$inv.IndexOf($end,$startIndex)
  if($endIndex -lt 0){throw "Encontré el inicio del cuadro avanzado pero no su cierre."}
  $endIndex += $end.Length
  # También quitar saltos inmediatamente posteriores para que no quede hueco.
  while($endIndex -lt $inv.Length -and ($inv[$endIndex] -eq "`r" -or $inv[$endIndex] -eq "`n")){$endIndex++}
  $inv=$inv.Substring(0,$startIndex)+$inv.Substring($endIndex)
}

# ---------------------------------------------------------
# 3. Agregar botón "Ahorro tarifario" junto a Consumo/Importe/Demanda/FP
# ---------------------------------------------------------
$button='<button className={metric==="pf"?"active":""} onClick={()=>setMetric("pf")}>Factor potencia</button>'
if(-not $inv.Contains($button)){
  throw "No encontré el botón Factor potencia para insertar Ahorro tarifario."
}
if($inv -notmatch '>Ahorro tarifario</button>'){
  $inv=$inv.Replace($button,$button+'<button className={metric==="tariff"?"active":""} onClick={()=>setMetric("tariff")}>Ahorro tarifario</button>')
}

# ---------------------------------------------------------
# 4. Reemplazar el gráfico por vista tarifaria cuando se selecciona esa pestaña
# ---------------------------------------------------------
$trend='<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>'
if(-not $inv.Contains($trend)){
  throw "No encontré InvoiceTrend para reemplazarlo."
}

$tariffView=@'
{metric==="tariff"?<div className="invoice-tariff-tab">
          <div className="invoice-tariff-tab-summary">
            <div>
              <span>FACTURA ANALIZADA</span>
              <b>{periodOf(selected)}</b>
              <small>{selected.current_tariff_code||"S/D"} · {currentVoltage||"S/D"}</small>
            </div>
            <div>
              <span>AHORRO TARIFARIO PROPUESTO</span>
              <b>{money.format(
                Math.max(
                  tariffSaving,
                  Number(optimization?.t4?.monthly_saving_before_taxes||0),
                  currentVoltage==="BT"?Number(optimization?.mt?.monthly_saving_before_taxes||0):0,
                  Number(optimization?.t3?.monthly_saving_before_taxes||0)
                )
              )}</b>
              <small>mensual estimado · según la mejor alternativa aplicable</small>
            </div>
          </div>

          <div className="invoice-tariff-options">
            {tariffSaving>0&&<article className="recommended">
              <span>CAMBIO DE CATEGORÍA</span>
              <h4>{selected.current_tariff_code||"Actual"} → categoría recomendada</h4>
              <b>{money.format(tariffSaving)}/mes</b>
              <small>Simulación tarifaria del período seleccionado.</small>
            </article>}

            {isT3&&optimization&&<article className={Number(optimization.t3.monthly_saving_before_taxes||0)>0?"recommended":""}>
              <span>T3 · POTENCIA POR FRANJA</span>
              <h4>Punta / fuera de punta</h4>
              <div className="invoice-tariff-values">
                <p><small>Contratada</small><b>{contractedBand.peak>0?nf.format(contractedBand.peak):"S/D"} / {contractedBand.offPeak>0?nf.format(contractedBand.offPeak):"S/D"} kW</b></p>
                <p><small>Recomendada</small><b>{optimization.t3.recommended_peak_kw>0?nf.format(optimization.t3.recommended_peak_kw):"S/D"} / {optimization.t3.recommended_off_peak_kw>0?nf.format(optimization.t3.recommended_off_peak_kw):"S/D"} kW</b></p>
              </div>
              <b>{optimization.t3.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.t3.monthly_saving_before_taxes))}/mes`:"Sin ahorro valorizado"}</b>
              <small>{contractedBand.offPeak<=0?"La factura no informa claramente la potencia contratada fuera de punta.":"Comparación con las máximas registradas por franja."}</small>
            </article>}

            {optimization?.t4.status==="candidate"&&<article className="recommended">
              <span>CAMBIO T3 → T4</span>
              <h4>{selected.current_tariff_code||"T3"} → {optimization.t4.target_tariff||"T4"}</h4>
              <div className="invoice-tariff-values">
                <p><small>Costo actual simulado</small><b>{optimization.t4.current_t3_cost_before_taxes!=null?money.format(Number(optimization.t4.current_t3_cost_before_taxes)):"S/D"}</b></p>
                <p><small>Costo T4 simulado</small><b>{optimization.t4.t4_cost_before_taxes!=null?money.format(Number(optimization.t4.t4_cost_before_taxes)):"S/D"}</b></p>
              </div>
              <b>{optimization.t4.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.t4.monthly_saving_before_taxes))}/mes`:"Requiere validación"}</b>
              <small>{optimization.t4.months_over_100kw_last12}/12 meses con demanda ≥100 kW · requiere contrato EPEN.</small>
            </article>}

            {currentVoltage==="BT"&&optimization&&["strong","candidate","preliminary"].includes(optimization.mt.status)&&<article className="recommended">
              <span>CAMBIO DE NIVEL DE TENSIÓN</span>
              <h4>BT → MT</h4>
              <div className="invoice-tariff-values">
                <p><small>BT simulado</small><b>{optimization.mt.current_bt_cost_before_taxes!=null?money.format(Number(optimization.mt.current_bt_cost_before_taxes)):"S/D"}</b></p>
                <p><small>MT simulado</small><b>{optimization.mt.simulated_mt_cost_before_taxes!=null?money.format(Number(optimization.mt.simulated_mt_cost_before_taxes)):"S/D"}</b></p>
              </div>
              <b>{optimization.mt.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.mt.monthly_saving_before_taxes))}/mes`:"Requiere factibilidad"}</b>
              <small>Solo se muestra porque este suministro está actualmente en Baja Tensión.</small>
            </article>}

            {!tariffSaving&&!(isT3&&optimization)&&optimization?.t4.status!=="candidate"&&!(currentVoltage==="BT"&&optimization&&["strong","candidate","preliminary"].includes(optimization.mt.status))&&
              <div className="invoice-tariff-empty">No se detectó un cambio tarifario valorizado para esta factura.</div>}
          </div>

          <div className="invoice-tariff-tab-note">
            Los escenarios T3/T4/BT→MT se muestran antes de impuestos. T4 y el cambio de nivel de tensión requieren validación de EPEN.
          </div>
        </div>:<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}
'@

$inv=$inv.Replace($trend,$tariffView)

# ---------------------------------------------------------
# 5. Evitar que InvoiceTrend reciba tariff por tipado:
# metricValue/ fmt quedan con fallback, pero el componente solo se monta con != tariff.
# ---------------------------------------------------------

Set-Content $invoicePath $inv -Encoding UTF8

# ---------------------------------------------------------
# 6. CSS nuevo
# ---------------------------------------------------------
$css=Get-Content $cssPath -Raw
if($css -notmatch 'EPEN ADVANCED V4'){
$styles=@'

/* EPEN ADVANCED V4 */
.invoice-analysis-metrics{flex-wrap:wrap}
.invoice-analysis-metrics button:last-child{min-width:122px}
.invoice-tariff-tab{padding:22px 24px 24px}
.invoice-tariff-tab-summary{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px}
.invoice-tariff-tab-summary>div{display:grid;gap:4px;padding:14px 16px;border:1px solid #e2e8f0;border-radius:12px;background:#f8fafc}
.invoice-tariff-tab-summary span{font-size:10px;font-weight:900;letter-spacing:.08em;color:#64748b}
.invoice-tariff-tab-summary b{font-size:20px;color:#0f172a}
.invoice-tariff-tab-summary>div:last-child{background:#ecfdf5;border-color:#a7f3d0}
.invoice-tariff-tab-summary>div:last-child b{color:#047857}
.invoice-tariff-tab-summary small{color:#64748b}
.invoice-tariff-options{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
.invoice-tariff-options article{display:grid;align-content:start;gap:7px;min-height:175px;padding:16px;border:1px solid #e2e8f0;border-radius:14px;background:#fff}
.invoice-tariff-options article.recommended{border-color:#86efac;background:#f0fdf4}
.invoice-tariff-options article>span{font-size:10px;font-weight:900;letter-spacing:.07em;color:#64748b}
.invoice-tariff-options article h4{margin:0;font-size:17px;color:#0f172a}
.invoice-tariff-options article>b{font-size:17px;color:#047857}
.invoice-tariff-options article>small{color:#64748b;font-size:11px;line-height:1.4}
.invoice-tariff-values{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.invoice-tariff-values p{display:grid;gap:3px;margin:0;padding:9px;border-radius:9px;background:rgba(255,255,255,.75)}
.invoice-tariff-values p small{color:#64748b;font-size:10px}
.invoice-tariff-values p b{font-size:13px;color:#0f172a}
.invoice-tariff-empty{grid-column:1/-1;padding:28px;text-align:center;border:1px dashed #cbd5e1;border-radius:12px;color:#64748b;background:#f8fafc}
.invoice-tariff-tab-note{margin-top:13px;padding-top:12px;border-top:1px solid #e2e8f0;color:#64748b;font-size:11px}
@media(max-width:1100px){.invoice-tariff-options{grid-template-columns:1fr}.invoice-tariff-tab-summary{grid-template-columns:1fr}}
'@
Add-Content $cssPath $styles -Encoding UTF8
}

Write-Host ""
Write-Host "OK - EPEN Optimización V4 aplicada." -ForegroundColor Green
Write-Host "Cambios:" -ForegroundColor Yellow
Write-Host "  - Se eliminó el cuadro superior ANÁLISIS TARIFARIO AVANZADO EPEN."
Write-Host "  - Se agregó la pestaña Ahorro tarifario junto a Consumo/Importe/Demanda/Factor potencia."
Write-Host "  - La pestaña muestra solo las alternativas aplicables a la factura seleccionada."
Write-Host "  - Si es MT no muestra BT -> MT."
Write-Host "Backup: $backup"
