$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if (Test-Path (Join-Path $Root "front\app\page.tsx")) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if (Test-Path (Join-Path $Parent "front\app\page.tsx")) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$path=Join-Path $Repo "front\app\page.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup="$path.bak-v15-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

# ------------------------------------------------------------
# 1) Tipos del resumen tarifario avanzado
# ------------------------------------------------------------
if($text -notmatch 'type AdvancedTariffSummaryMeter'){
  $marker='type TariffSavingResponse'
  $idx=$text.IndexOf($marker)
  if($idx -lt 0){throw "No encontré TariffSavingResponse."}
$type=@'
type AdvancedTariffSummaryMeter={
  meter_id:string;
  billing_period:string;
  current_tariff:string;
  recommended_tariff:string;
  monthly_saving:number;
  annualized_saving:number;
  available:boolean;
  resolution_number?:string|null;
};
type AdvancedTariffSummary={
  billing_period:string;
  monthly_saving:number;
  annualized_saving:number;
  candidate_count:number;
  valued_count:number;
  meters:AdvancedTariffSummaryMeter[];
};

'@
  $text=$text.Insert($idx,$type)
}

# ------------------------------------------------------------
# 2) Estado
# ------------------------------------------------------------
if($text -notmatch 'const\[advancedTariffSummary,setAdvancedTariffSummary\]'){
  $needle='const[epenOptimization,setEpenOptimization]=useState<EpenOptimizationMeter[]>([]);'
  if(-not $text.Contains($needle)){throw "No encontré estado epenOptimization."}
  $text=$text.Replace($needle,$needle+"`r`n"+'  const[advancedTariffSummary,setAdvancedTariffSummary]=useState<AdvancedTariffSummary|null>(null);')
}

# ------------------------------------------------------------
# 3) Cargar resumen avanzado para el período del dashboard
# ------------------------------------------------------------
if($text -notmatch '/tariff-saving-summary'){
  $marker='  const dashboardPeriodLabel='
  $idx=$text.IndexOf($marker)
  if($idx -lt 0){throw "No encontré dashboardPeriodLabel."}

  $lineEnd=$text.IndexOf("`n",$idx)
  if($lineEnd -lt 0){throw "No encontré fin de dashboardPeriodLabel."}
  $lineEnd++

$effect=@'
  useEffect(()=>{
    let cancelled=false;
    async function loadAdvancedTariffSummary(){
      if(!session||!orgId||!dashboardPeriod)return;
      try{
        const result=await api<AdvancedTariffSummary>(`/api/organizations/${orgId}/tariff-saving-summary?period=${dashboardPeriod}`,session);
        if(!cancelled)setAdvancedTariffSummary(result);
      }catch{
        if(!cancelled)setAdvancedTariffSummary(null);
      }
    }
    loadAdvancedTariffSummary();
    return()=>{cancelled=true};
  },[session,orgId,dashboardPeriod]);

'@
  $text=$text.Insert($lineEnd,$effect)
}

# ------------------------------------------------------------
# 4) Pasar advancedTariffSummary a InvoiceTable
# ------------------------------------------------------------
$oldCall='<InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} epenOptimization={epenOptimization} pendingMeters={visibleMissingPeriodMeters} period={controlPeriod} onSelect={openMeter}/>'
$newCall='<InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} epenOptimization={epenOptimization} advancedTariffSummary={advancedTariffSummary} pendingMeters={visibleMissingPeriodMeters} period={controlPeriod} onSelect={openMeter}/>'
if($text.Contains($oldCall)){
  $text=$text.Replace($oldCall,$newCall)
}elseif($text -notmatch 'advancedTariffSummary=\{advancedTariffSummary\}'){
  throw "No encontré la llamada a InvoiceTable."
}

# ------------------------------------------------------------
# 5) Firma de InvoiceTable
# ------------------------------------------------------------
$oldSig='function InvoiceTable({invoices,assessments,tariffSavings,epenOptimization,pendingMeters,period,onSelect}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];epenOptimization:EpenOptimizationMeter[];pendingMeters:Meter[];period:string;onSelect?:(i:Invoice)=>void})'
$newSig='function InvoiceTable({invoices,assessments,tariffSavings,epenOptimization,advancedTariffSummary,pendingMeters,period,onSelect}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];epenOptimization:EpenOptimizationMeter[];advancedTariffSummary:AdvancedTariffSummary|null;pendingMeters:Meter[];period:string;onSelect?:(i:Invoice)=>void})'
if($text.Contains($oldSig)){
  $text=$text.Replace($oldSig,$newSig)
}elseif($text -notmatch 'function InvoiceTable\(\{invoices,assessments,tariffSavings,epenOptimization,advancedTariffSummary'){
  throw "No encontré la firma de InvoiceTable."
}

# ------------------------------------------------------------
# 6) Reemplazar cálculo tarifario de cada fila
# ------------------------------------------------------------
$oldCalc='tariffSaving=Math.max(Number(tariffResult?.monthly_saving_with_vat||0),Number(assessment?.tariff_monthly_saving||0),Math.max(0,Number(assessment?.tariff_current_simulated||0)-Number(assessment?.tariff_recommended_simulated||0))),estimatedSaving=powerSaving+reactiveSaving+tariffSaving,measures=[powerSaving>0?"Potencia contratada":"",tariffSaving>0?"Tarifaria":"",reactiveSaving>0?"Factor de potencia":""].filter(Boolean);'

$newCalc='advancedTariffRow=advancedTariffSummary?.billing_period===period?advancedTariffSummary.meters.find(t=>t.meter_id===i.meter_id&&String(t.billing_period).slice(0,7)===period&&t.available):undefined,advancedTariffSaving=Number(advancedTariffRow?.monthly_saving||0),legacyTariffSaving=Math.max(Number(tariffResult?.monthly_saving_with_vat||0),Number(assessment?.tariff_monthly_saving||0),Math.max(0,Number(assessment?.tariff_current_simulated||0)-Number(assessment?.tariff_recommended_simulated||0))),tariffSaving=advancedTariffSaving>0?advancedTariffSaving:legacyTariffSaving,estimatedSaving=powerSaving+reactiveSaving+tariffSaving,measures=[powerSaving>0?"Potencia contratada":"",tariffSaving>0?(advancedTariffSaving>0?`${advancedTariffRow?.current_tariff||"Tarifa"} → ${advancedTariffRow?.recommended_tariff||"T4"}`:"Tarifaria"):"",reactiveSaving>0?"Factor de potencia":""].filter(Boolean);'

if($text.Contains($oldCalc)){
  $text=$text.Replace($oldCalc,$newCalc)
}elseif($text -notmatch 'advancedTariffRow=advancedTariffSummary'){
  throw "No encontré el cálculo tariffSaving dentro de InvoiceTable."
}

# ------------------------------------------------------------
# 7) Encabezado y detalle anual: ya no decir que TODO incluye IVA 30%.
#    Potencia/reactiva siguen con factor 1,30; T4 es antes de impuestos.
# ------------------------------------------------------------
$text=$text.Replace(
  '<th>Ahorro anual estimado (IVA 30%)</th>',
  '<th>Ahorro anual estimado</th>'
)

$oldAnnual='<strong className="row-saving">{money.format(estimatedSaving*12)}<small>Mensual con IVA {money.format(estimatedSaving)} × 12</small></strong>'
$newAnnual='<strong className="row-saving">{money.format(estimatedSaving*12)}<small>{money.format(estimatedSaving)} mensual × 12{advancedTariffSaving>0?" · tarifa antes de impuestos":""}</small></strong>'
if($text.Contains($oldAnnual)){
  $text=$text.Replace($oldAnnual,$newAnnual)
}

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - V15 aplicada." -ForegroundColor Green
Write-Host "La tabla de Facturas ahora suma:" -ForegroundColor Yellow
Write-Host "  - Potencia contratada"
Write-Host "  - Cambio T3/T3A real -> T4 simulado"
Write-Host "  - Factor de potencia"
Write-Host ""
Write-Host "Y en Medidas de ahorro mostrará también T3A -> T4-MT cuando corresponda."
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "IMPORTANTE: requiere el endpoint V14 desplegado en Render."
