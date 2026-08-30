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

# 1) Tipos: agregar potencia fuera de punta
$inv=$inv.Replace(
'contracted_kw_peak?:number;sites?:{name?:string;address?:string};',
'contracted_kw_peak?:number;contracted_kw_off_peak?:number;sites?:{name?:string;address?:string};'
)
$inv=$inv.Replace(
'tariff_name?:string;voltage_level?:string;contracted_kw_peak?:number;vat_amount?:number;previous_debt_amount?:number;',
'tariff_name?:string;voltage_level?:string;contracted_kw_peak?:number;contracted_kw_off_peak?:number;vat_amount?:number;previous_debt_amount?:number;'
)

# 2) Función para obtener las 2 capacidades, incluso si vienen en líneas DEP/DFP
if($inv -notmatch 'function contractedBands'){
$needle='function periodOf(i:Invoice){return String(i.billing_period||i.period_start).slice(0,7)}'
$insert=@'
function contractedBands(i:Invoice){
  const lines=i.invoice_lines||[];
  const dep=Math.max(0,...lines.filter(x=>x.concept_code==="DEP"||x.concept_code==="DEM").map(x=>Number(x.quantity||0)));
  const dfp=Math.max(0,...lines.filter(x=>x.concept_code==="DFP").map(x=>Number(x.quantity||0)));
  const peak=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||dep||0);
  const offPeak=Number(i.contracted_kw_off_peak||i.meters?.contracted_kw_off_peak||dfp||0);
  return{peak,offPeak};
}
'@
$inv=$inv.Replace($needle,$needle+"`r`n"+$insert)
}

# 3) values usa punta para el cálculo tradicional
$old='const contracted=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||0);'
if($inv.Contains($old)){
  $inv=$inv.Replace($old,'const contracted=contractedBands(i).peak;')
}

# 4) Variables del análisis individual
$needle2='  const v=values(selected);'
if($inv.Contains($needle2) -and $inv -notmatch 'const contractedBand=contractedBands'){
  $inv=$inv.Replace($needle2,$needle2+"`r`n"+'  const contractedBand=contractedBands(selected);'+"`r`n"+'  const isT3=["T3","T3A"].includes(String(selected.current_tariff_code||"").toUpperCase());'+"`r`n"+'  const currentVoltage=String(selected.voltage_level||selected.meters?.voltage_level||"").toUpperCase();')
}

# 5) KPIs superiores: reemplazar potencia única por dos tarjetas solo en T3
$oldKpi='<article className={excess>0?"warn":""}><span>Potencia contratada</span><b>{nf.format(v.contracted)} kW</b><small>{excess>0?`${nf.format(excess)} kW por encima de la demanda`:"sin sobrante detectado"}</small></article>'
$newKpi=@'
{isT3?<>
        <article className={contractedBand.peak>0?"warn":""}><span>Potencia contratada punta</span><b>{contractedBand.peak>0?`${nf.format(contractedBand.peak)} kW`:"S/D"}</b><small>capacidad convenida en horas punta</small></article>
        <article className={contractedBand.offPeak>0?"warn":""}><span>Potencia contratada fuera punta</span><b>{contractedBand.offPeak>0?`${nf.format(contractedBand.offPeak)} kW`:"S/D"}</b><small>capacidad convenida en resto + valle</small></article>
      </>:<article className={excess>0?"warn":""}><span>Potencia contratada</span><b>{nf.format(v.contracted)} kW</b><small>{excess>0?`${nf.format(excess)} kW por encima de la demanda`:"sin sobrante detectado"}</small></article>}
'@
if(-not $inv.Contains($oldKpi)){throw "No encontré la tarjeta Potencia contratada para reemplazar."}
$inv=$inv.Replace($oldKpi,$newKpi)

# 6) Reemplazar bloque avanzado completo por uno condicional según factura
$start='      {optimization&&<section className="invoice-analysis-panel epen-individual-analysis">'
$end='      </section>}'
$startIndex=$inv.IndexOf($start)
if($startIndex -lt 0){throw "No encontré el bloque EPEN avanzado V2."}
$endIndex=$inv.IndexOf($end,$startIndex)
if($endIndex -lt 0){throw "No encontré el cierre del bloque EPEN avanzado."}
$endIndex += $end.Length

$newBlock=@'
      {optimization&&(isT3||optimization.t4.status==="candidate"||(currentVoltage==="BT"&&["strong","candidate","preliminary"].includes(optimization.mt.status)))&&<section className="invoice-analysis-panel epen-individual-analysis">
        <div className="epen-individual-head">
          <div><span>ANÁLISIS TARIFARIO AVANZADO EPEN</span><h3>Oportunidades que aplican a esta factura</h3><p>Solo se muestran alternativas compatibles con la tarifa y nivel de tensión actuales. Valores antes de impuestos.</p></div>
        </div>
        <div className={`epen-individual-grid epen-cols-${[
          isT3,
          optimization.t4.status==="candidate",
          currentVoltage==="BT"&&["strong","candidate","preliminary"].includes(optimization.mt.status)
        ].filter(Boolean).length}`}>
          {isT3&&<article className={optimization.t3.status==="candidate"?"candidate":""}>
            <span>T3 · Potencia contratada por franja</span>
            <b>Punta / fuera de punta</b>
            <small>Contratada: {contractedBand.peak>0?nf.format(contractedBand.peak):"S/D"} / {contractedBand.offPeak>0?nf.format(contractedBand.offPeak):"S/D"} kW</small>
            <small>Máxima registrada 12m: {optimization.t3.max_registered_peak_12m_kw>0?nf.format(optimization.t3.max_registered_peak_12m_kw):"S/D"} / {optimization.t3.max_registered_off_peak_12m_kw>0?nf.format(optimization.t3.max_registered_off_peak_12m_kw):"S/D"} kW</small>
            {optimization.t3.recommended_peak_kw>0&&optimization.t3.recommended_off_peak_kw>0&&<small>Recomendada: {nf.format(optimization.t3.recommended_peak_kw)} / {nf.format(optimization.t3.recommended_off_peak_kw)} kW</small>}
            <strong>{optimization.t3.monthly_saving_before_taxes!=null?`${money.format(optimization.t3.monthly_saving_before_taxes)}/mes`:contractedBand.offPeak<=0?"Falta identificar potencia fuera de punta":"Faltan demandas registradas por franja"}</strong>
          </article>}

          {optimization.t4.status==="candidate"&&<article className="candidate">
            <span>Cambio T3 → T4</span>
            <b>Candidato {optimization.t4.target_tariff||"T4"}</b>
            <small>{optimization.t4.months_over_100kw_last12}/12 meses con demanda ≥100 kW</small>
            {optimization.t4.current_t3_cost_before_taxes!=null&&<small>T3 simulado: {money.format(Number(optimization.t4.current_t3_cost_before_taxes))}</small>}
            {optimization.t4.t4_cost_before_taxes!=null&&<small>T4 simulado: {money.format(Number(optimization.t4.t4_cost_before_taxes))}</small>}
            <strong>{optimization.t4.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.t4.monthly_saving_before_taxes))}/mes`:"Requiere validación EPEN"}</strong>
          </article>}

          {currentVoltage==="BT"&&["strong","candidate","preliminary"].includes(optimization.mt.status)&&<article className="candidate">
            <span>Baja Tensión → Media Tensión</span>
            <b>{optimization.mt.status==="strong"?"Candidato fuerte":optimization.mt.status==="candidate"?"Candidato":"Estudio preliminar"}</b>
            <small>Máxima 12m: {nf.format(optimization.max_demand_12m_kw)} kW</small>
            {optimization.mt.current_bt_cost_before_taxes!=null&&<small>BT simulado: {money.format(Number(optimization.mt.current_bt_cost_before_taxes))}</small>}
            {optimization.mt.simulated_mt_cost_before_taxes!=null&&<small>MT simulado: {money.format(Number(optimization.mt.simulated_mt_cost_before_taxes))}</small>}
            <strong>{optimization.mt.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.mt.monthly_saving_before_taxes))}/mes`:"Requiere factibilidad EPEN"}</strong>
          </article>}
        </div>
      </section>}
'@

$inv=$inv.Substring(0,$startIndex)+$newBlock+$inv.Substring($endIndex)
Set-Content $invoicePath $inv -Encoding UTF8

# 7) CSS: 2 columnas cuando solo aplican T3+T4
$css=Get-Content $cssPath -Raw
if($css -notmatch 'epen-cols-2'){
Add-Content $cssPath @'

/* EPEN ADVANCED V3 */
.epen-individual-grid.epen-cols-1{grid-template-columns:minmax(0,1fr)}
.epen-individual-grid.epen-cols-2{grid-template-columns:repeat(2,minmax(0,1fr))}
.epen-individual-grid.epen-cols-3{grid-template-columns:repeat(3,minmax(0,1fr))}
.invoice-analysis-kpis:has(article:nth-child(7)){grid-template-columns:repeat(7,minmax(0,1fr))}
@media(max-width:1450px){.invoice-analysis-kpis:has(article:nth-child(7)){grid-template-columns:repeat(4,minmax(0,1fr))}}
@media(max-width:1000px){.epen-individual-grid.epen-cols-2,.epen-individual-grid.epen-cols-3{grid-template-columns:1fr}.invoice-analysis-kpis:has(article:nth-child(7)){grid-template-columns:repeat(2,minmax(0,1fr))}}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - EPEN Optimización V3 aplicada." -ForegroundColor Green
Write-Host "Cambios:" -ForegroundColor Yellow
Write-Host "  - T3 muestra Potencia contratada PUNTA y FUERA DE PUNTA arriba."
Write-Host "  - El análisis avanzado muestra SOLO lo aplicable a esa factura."
Write-Host "  - Si el suministro ya es MT, NO aparece BT -> MT."
Write-Host "  - En el caso T3A-MT de Planta Confluencia deberían quedar T3 + T4."
Write-Host "Backup: $backup"
