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
$backup="$path.bak-v18-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

# Reemplazar el bloque de cálculo tarifario por fila.
$old='advancedTariffRow=advancedTariffSummary?.billing_period===period?advancedTariffSummary.meters.find(t=>t.meter_id===i.meter_id&&String(t.billing_period).slice(0,7)===period&&t.available):undefined,advancedTariffSaving=Number(advancedTariffRow?.monthly_saving||0),legacyTariffSaving=Math.max(Number(tariffResult?.monthly_saving_with_vat||0),Number(assessment?.tariff_monthly_saving||0),Math.max(0,Number(assessment?.tariff_current_simulated||0)-Number(assessment?.tariff_recommended_simulated||0))),tariffSaving=advancedTariffSaving>0?advancedTariffSaving:legacyTariffSaving,estimatedSaving=powerSaving+reactiveSaving+tariffSaving,measures=[powerSaving>0?"Potencia contratada":"",tariffSaving>0?(advancedTariffSaving>0?`${advancedTariffRow?.current_tariff||"Tarifa"} → ${advancedTariffRow?.recommended_tariff||"T4"}`:"Tarifaria"):"",reactiveSaving>0?"Factor de potencia":""].filter(Boolean);'

$new='advancedTariffRow=advancedTariffSummary?.billing_period===period?advancedTariffSummary.meters.find(t=>(t.meter_id===i.meter_id||String((t as any).meter_number||"")===String(i.meters?.meter_number||"")||String((t as any).supply_number||"")===String(i.meters?.supply_number||""))&&String(t.billing_period).slice(0,7)===period&&t.available):undefined,advancedSummarySaving=Number(advancedTariffRow?.monthly_saving||0),optimizationMtSaving=advanced&&["strong","candidate","preliminary"].includes(advanced.mt.status)?Number(advanced.mt.monthly_saving_before_taxes||0):0,optimizationT4Saving=advanced?.t4.status==="candidate"?Number(advanced.t4.monthly_saving_before_taxes||0):0,advancedTariffSaving=advancedSummarySaving>0?advancedSummarySaving:optimizationMtSaving>0?optimizationMtSaving:optimizationT4Saving,legacyTariffSaving=Math.max(Number(tariffResult?.monthly_saving_with_vat||0),Number(assessment?.tariff_monthly_saving||0),Math.max(0,Number(assessment?.tariff_current_simulated||0)-Number(assessment?.tariff_recommended_simulated||0))),tariffSaving=advancedTariffSaving>0?advancedTariffSaving:legacyTariffSaving,advancedTariffLabel=advancedSummarySaving>0?`${advancedTariffRow?.current_tariff||"Tarifa"} → ${advancedTariffRow?.recommended_tariff||"Propuesta"}`:optimizationMtSaving>0?`${String(i.current_tariff_code||i.meters?.current_tariff_code||"Tarifa")}-BT → ${String(i.current_tariff_code||i.meters?.current_tariff_code||"Tarifa")}-MT`:optimizationT4Saving>0?`${String(i.current_tariff_code||i.meters?.current_tariff_code||"T3")}-${String(i.voltage_level||i.meters?.voltage_level||"MT")} → ${advanced?.t4.target_tariff||"T4"}`:"Tarifaria",estimatedSaving=powerSaving+reactiveSaving+tariffSaving,measures=[powerSaving>0?"Potencia contratada":"",tariffSaving>0?(advancedTariffSaving>0?advancedTariffLabel:"Tarifaria"):"",reactiveSaving>0?"Factor de potencia":""].filter(Boolean);'

if(-not $text.Contains($old)){
  throw "No encontré el bloque de cálculo de InvoiceTable esperado. No hice cambios."
}

$text=$text.Replace($old,$new)

# Aclarar la fuente del ahorro cuando viene del fallback de optimización.
$oldSmall='{money.format(estimatedSaving)} mensual × 12{advancedTariffSaving>0?" · tarifa antes de impuestos":""}'
$newSmall='{money.format(estimatedSaving)} mensual × 12{advancedTariffSaving>0?" · tarifa antes de impuestos":""}'
# igual visualmente, no hace falta cambiar; mantenemos para compatibilidad.

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - V18 aplicada." -ForegroundColor Green
Write-Host "InvoiceTable ahora busca ahorro tarifario por:" -ForegroundColor Yellow
Write-Host "  1. meter_id en tariff-saving-summary"
Write-Host "  2. número de medidor / suministro"
Write-Host "  3. fallback epenOptimization.mt"
Write-Host "  4. fallback epenOptimization.t4"
Write-Host "  5. cálculo tarifario legacy"
Write-Host ""
Write-Host "Para medidor 502105395 debe aparecer T3A-BT -> T3A-MT."
Write-Host "Backup: $backup"
