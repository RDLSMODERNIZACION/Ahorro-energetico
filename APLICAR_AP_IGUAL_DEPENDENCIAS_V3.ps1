$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$invoice = Join-Path $repo "front\app\invoice-analysis-panel.tsx"
$public = Join-Path $repo "front\app\public-lighting-panel.tsx"

foreach($file in @($invoice,$public)){
    if(-not (Test-Path $file)){
        throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $invoice "$invoice.bak-$stamp" -Force
Copy-Item $public "$public.bak-$stamp" -Force

function Replace-RegexOnce {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    $rx = [regex]::new($Pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
    if(-not $rx.IsMatch($Text)){
        throw "No encontré el bloque esperado: $Label. No se aplicó el cambio."
    }
    return $rx.Replace($Text,$Replacement,1)
}

# =========================================================
# A) InvoiceAnalysisPanel: permitir reutilizar EXACTAMENTE
#    la misma pantalla para Alumbrado Público.
# =========================================================
$txt = Get-Content $invoice -Raw -Encoding UTF8

# Firma con props opcionales de contexto.
$pattern = 'export function InvoiceAnalysisPanel\(\{invoice,history,tariffSavings,optimization,onClose\}:\{invoice:Invoice;history:Invoice\[\];tariffSavings:TariffSaving\[\];optimization\?:EpenOptimizationMeter;onClose:\(\)=>void\}\)\{'
$replacement = @'
export function InvoiceAnalysisPanel({
  invoice,history,tariffSavings,optimization,onClose,
  backLabel="← Volver a facturas",
  analysisLabel="ANÁLISIS INDIVIDUAL DE FACTURA",
  allowNameEdit=true,
  simpleTariffHistory,
  hideLocationEditor=false
}:{
  invoice:Invoice;
  history:Invoice[];
  tariffSavings:TariffSaving[];
  optimization?:EpenOptimizationMeter;
  onClose:()=>void;
  backLabel?:string;
  analysisLabel?:string;
  allowNameEdit?:boolean;
  simpleTariffHistory?:Array<{billing_period:string;tariff_code?:string|null;invoice_number?:string|null;total_amount?:number|null}>;
  hideLocationEditor?:boolean;
}){
'@
$txt = Replace-RegexOnce $txt $pattern $replacement "firma de InvoiceAnalysisPanel"

# Botón volver y rótulo superior.
$txt = $txt.Replace('<button className="invoice-analysis-back" onClick={onClose}>← Volver a facturas</button>',
                    '<button className="invoice-analysis-back" onClick={onClose}>{backLabel}</button>')
$txt = $txt.Replace('<small>ANÁLISIS INDIVIDUAL DE FACTURA</small>',
                    '<small>{analysisLabel}</small>')

# En AP no mostramos "Editar nombre"; en dependencias sigue exactamente como estaba.
$txt = $txt.Replace(
    '<button className="invoice-edit-name" onClick={()=>{setNameDraft(displayName);setEditingName(true)}}>✎ Editar nombre</button>',
    '{allowNameEdit&&<button className="invoice-edit-name" onClick={()=>{setNameDraft(displayName);setEditingName(true)}}>✎ Editar nombre</button>}'
)

# Tarifaria simple para AP. Para dependencias NO cambia el análisis tarifario existente.
$needle = '{metric==="tariff" ? (() => {'
$insert = @'
{metric==="tariff"&&simpleTariffHistory?.length ? (
          <div className="invoice-tariff-detail-view">
            <div className="invoice-tariff-period-detail">
              <div className="invoice-tariff-period-head">
                <div>
                  <span>HISTÓRICO TARIFARIO</span>
                  <h4>{periodOf(selected)} · {selected.current_tariff_code||"S/D"}</h4>
                  <p>Tarifa informada en las facturas disponibles del suministro.</p>
                </div>
                <div className="saving">
                  <span>TARIFA ACTUAL</span>
                  <b>{selected.current_tariff_code||"S/D"}</b>
                  <small>período seleccionado</small>
                </div>
              </div>
              <div className="invoice-analysis-table-wrap">
                <table className="invoice-analysis-table">
                  <thead><tr><th>Período</th><th>Tarifa</th><th>Factura</th><th>Importe</th></tr></thead>
                  <tbody>{[...simpleTariffHistory].sort((a,b)=>b.billing_period.localeCompare(a.billing_period)).map((row,index)=><tr key={`${row.billing_period}-${index}`}>
                    <td><b>{row.billing_period}</b></td>
                    <td><b>{row.tariff_code||"S/D"}</b></td>
                    <td>{row.invoice_number||"S/D"}</td>
                    <td><b>{row.total_amount==null?"—":money.format(Number(row.total_amount||0))}</b></td>
                  </tr>)}</tbody>
                </table>
              </div>
            </div>
          </div>
        ) : metric==="tariff" ? (() => {
'@
if(-not $txt.Contains($needle)){ throw "No encontré el bloque de Tarifaria en InvoiceAnalysisPanel." }
$txt = $txt.Replace($needle,$insert)

# Ocultar editor de ubicación en AP; dependencias sigue igual.
$locPattern = '<MeterLocationEditor meterId=\{selected\.meter_id\} label=\{`\$\{m\?\.service_name\|\|m\?\.sites\?\.name\|\|"Servicio"\} · Medidor \$\{m\?\.meter_number\|\|"S/D"\}`\}/>'
$locReplacement = '{!hideLocationEditor&&<MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>}'

$rxLoc = [regex]::new($locPattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
if($rxLoc.IsMatch($txt)){
    $txt = $rxLoc.Replace($txt,$locReplacement,1)
} else {
    # Variante simple si el formato no coincide exactamente.
    $simpleOld = '<MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>'
    if($txt.Contains($simpleOld)){
        $txt = $txt.Replace($simpleOld,$locReplacement)
    }
}

Set-Content $invoice -Value $txt -Encoding UTF8

# =========================================================
# B) Alumbrado Público:
#    NO intentar encontrar la factura en invoices normales,
#    porque AP usa public_lighting_invoices (otra tabla).
#    Adaptamos sus datos al mismo InvoiceAnalysisPanel.
# =========================================================
$pl = Get-Content $public -Raw -Encoding UTF8

# Reemplaza selectedInvoice por un adaptador AP -> InvoiceAnalysisPanel.
$selectedPattern = 'const selectedInvoice=selected\?\([\s\S]*?\):null;'
$selectedReplacement = @'
const apHistoryInvoices=selected?[...selected.history].map((h,index)=>({
    id:`ap-${selected.public_lighting_meter_id}-${h.billing_period}-${index}`,
    meter_id:`ap-${selected.public_lighting_meter_id}`,
    invoice_number:h.invoice_number||undefined,
    billing_period:h.billing_period,
    period_start:`${h.billing_period}-01`,
    period_end:`${h.billing_period}-28`,
    total_amount:Number(h.total_amount||0),
    current_tariff_code:h.tariff_code||selected.tariff_code||undefined,
    tariff_name:h.tariff_code||selected.tariff_code||undefined,
    meters:{
      id:`ap-${selected.public_lighting_meter_id}`,
      tracking_code:`AP-${selected.public_lighting_meter_id}`,
      meter_number:selected.meter_number||undefined,
      supply_number:selected.supply_number||undefined,
      service_name:selected.address||"Alumbrado público",
      current_tariff_code:h.tariff_code||selected.tariff_code||undefined,
      sites:{name:selected.address||"Alumbrado público",address:selected.address||undefined}
    },
    invoice_measurements:[{
      active_energy_kwh:Number(h.active_energy_kwh||0),
      measurement_type:"Alumbrado público",
      meter_number:selected.meter_number||undefined
    }],
    invoice_lines:[]
  })):[];

  const apSelectedInvoice=selected?(
    apHistoryInvoices.find(i=>String(i.billing_period).slice(0,7)===String(selected.billing_period).slice(0,7))
    ||apHistoryInvoices.at(-1)
    ||{
      id:`ap-${selected.public_lighting_meter_id}-${selected.billing_period}`,
      meter_id:`ap-${selected.public_lighting_meter_id}`,
      invoice_number:selected.invoice_number||undefined,
      billing_period:selected.billing_period,
      period_start:`${selected.billing_period}-01`,
      period_end:`${selected.billing_period}-28`,
      total_amount:Number(selected.total_amount||0),
      current_tariff_code:selected.tariff_code||undefined,
      meters:{
        id:`ap-${selected.public_lighting_meter_id}`,
        tracking_code:`AP-${selected.public_lighting_meter_id}`,
        meter_number:selected.meter_number||undefined,
        supply_number:selected.supply_number||undefined,
        service_name:selected.address||"Alumbrado público",
        current_tariff_code:selected.tariff_code||undefined,
        sites:{name:selected.address||"Alumbrado público",address:selected.address||undefined}
      },
      invoice_measurements:[{
        active_energy_kwh:Number(selected.active_energy_kwh||0),
        measurement_type:"Alumbrado público",
        meter_number:selected.meter_number||undefined
      }],
      invoice_lines:[]
    }
  ):null;
'@
$pl = Replace-RegexOnce $pl $selectedPattern $selectedReplacement "adaptador de factura AP"

# Reemplaza los dos renderizados (nuevo + fallback viejo) por UNO SOLO,
# siempre usando exactamente InvoiceAnalysisPanel.
$renderPattern = '\{selected&&selectedInvoice&&<InvoiceAnalysisPanel[\s\S]*?\{selected&&!selectedInvoice&&<IndividualAnalysis row=\{selected\} onClose=\{\(\)=>setSelected\(null\)\}/>\}'
$renderReplacement = @'
{selected&&apSelectedInvoice&&<InvoiceAnalysisPanel
      invoice={apSelectedInvoice}
      history={apHistoryInvoices.length?apHistoryInvoices:[apSelectedInvoice]}
      tariffSavings={[]}
      optimization={undefined}
      onClose={()=>setSelected(null)}
      backLabel="← Volver a Alumbrado Público"
      analysisLabel="ANÁLISIS INDIVIDUAL · ALUMBRADO PÚBLICO"
      allowNameEdit={false}
      simpleTariffHistory={selected.history}
      hideLocationEditor={true}
    />}
'@
$pl = Replace-RegexOnce $pl $renderPattern $renderReplacement "render del análisis individual AP"

Set-Content $public -Value $pl -Encoding UTF8

Write-Host ""
Write-Host "AP = MISMO ANALISIS QUE DEPENDENCIAS aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Ahora Alumbrado Público usa SIEMPRE InvoiceAnalysisPanel." -ForegroundColor Cyan
Write-Host "Ya no puede caer al panel viejo de Resumen / Consumo / Importe / Tarifa."
Write-Host ""
Write-Host "Pestañas del análisis:" -ForegroundColor Cyan
Write-Host "  - Demanda"
Write-Host "  - Importe"
Write-Host "  - Factor de potencia"
Write-Host "  - Tarifaria"
Write-Host ""
Write-Host "IMPORTANTE:"
Write-Host "Los datos AP actuales del backend solo traen consumo, importe y tarifa."
Write-Host "Por eso Demanda y Factor de potencia aparecerán 0 / S/D hasta que esos"
Write-Host "campos existan en public_lighting_invoices o se vinculen con la factura completa."
Write-Host ""
Write-Host "Backups: .bak-$stamp"
Write-Host ""
Write-Host "Probar:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
