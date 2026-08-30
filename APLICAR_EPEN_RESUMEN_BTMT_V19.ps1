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
$backup="$path.bak-v19-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

$old=@'
  const legacyDashboardRateMonthly=tariffSavings.filter(x=>String(x.billing_period).slice(0,7)===dashboardPeriod).reduce((sum,x)=>sum+Number(x.monthly_saving_with_vat||0),0);
  const dashboardRateMonthly=advancedTariffSummary?.billing_period===dashboardPeriod
    ?Number(advancedTariffSummary.monthly_saving||0)
    :legacyDashboardRateMonthly;
'@

$new=@'
  const legacyDashboardRateMonthly=tariffSavings.filter(x=>String(x.billing_period).slice(0,7)===dashboardPeriod).reduce((sum,x)=>sum+Number(x.monthly_saving_with_vat||0),0);

  const dashboardAdvancedRows=advancedTariffSummary?.billing_period===dashboardPeriod
    ?advancedTariffSummary.meters.filter(x=>x.available&&Number(x.monthly_saving||0)>0)
    :[];

  const dashboardAdvancedMeterIds=new Set(dashboardAdvancedRows.map(x=>x.meter_id));

  const dashboardOptimizationFallbackRows=dashboardInvoices.map(i=>{
    if(dashboardAdvancedMeterIds.has(i.meter_id))return null;

    const opt=epenOptimization.find(x=>x.meter_id===i.meter_id);
    if(!opt)return null;

    const mtSaving=["strong","candidate","preliminary"].includes(opt.mt.status)
      ?Number(opt.mt.monthly_saving_before_taxes||0)
      :0;

    const t4Saving=opt.t4.status==="candidate"
      ?Number(opt.t4.monthly_saving_before_taxes||0)
      :0;

    const saving=mtSaving>0?mtSaving:t4Saving;
    if(saving<=0)return null;

    return{
      meter_id:i.meter_id,
      monthly_saving:saving,
      scenario:mtSaving>0?"mt":"t4"
    };
  }).filter((x):x is {meter_id:string;monthly_saving:number;scenario:"mt"|"t4"}=>Boolean(x));

  const dashboardOptimizationFallbackMonthly=dashboardOptimizationFallbackRows.reduce((sum,x)=>sum+x.monthly_saving,0);

  const dashboardRateMonthly=advancedTariffSummary?.billing_period===dashboardPeriod
    ?Number(advancedTariffSummary.monthly_saving||0)+dashboardOptimizationFallbackMonthly
    :legacyDashboardRateMonthly+dashboardOptimizationFallbackMonthly;

  const dashboardTariffValuedCount=
    dashboardAdvancedRows.length+
    dashboardOptimizationFallbackRows.length;
'@

if(-not $text.Contains($old)){
    throw "No encontré el bloque dashboardRateMonthly esperado."
}
$text=$text.Replace($old,$new)

# Replace hasTariff block if current version still only summary/legacy
$oldHas='const hasTariff=advancedTariffSummary?.billing_period===dashboardPeriod?advancedTariffSummary.meters.some(x=>x.meter_id===i.meter_id&&x.available&&Number(x.monthly_saving||0)>0):tariffSavings.some(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===dashboardPeriod&&Number(x.monthly_saving_with_vat||0)>0);'
$newHas='const hasTariff=dashboardAdvancedMeterIds.has(i.meter_id)||dashboardOptimizationFallbackRows.some(x=>x.meter_id===i.meter_id)||(advancedTariffSummary?.billing_period!==dashboardPeriod&&tariffSavings.some(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===dashboardPeriod&&Number(x.monthly_saving_with_vat||0)>0));'
if($text.Contains($oldHas)){
    $text=$text.Replace($oldHas,$newHas)
}

# Update dashboard card explanatory text/count
$pattern='<p>\{advancedTariffSummary\?\.billing_period===dashboardPeriod\?`T3/T3A real vs T4 simulada · \$\{advancedTariffSummary\.valued_count\} suministro\(s\) valorizado\(s\)\.`:"Diferencia contra la categoría recomendada para ese período\."\}</p>'
$replacement='<p>{advancedTariffSummary?.billing_period===dashboardPeriod?`Cambio tarifario valorizado · ${dashboardTariffValuedCount} suministro(s) · incluye T3/T3A→T4 y BT→MT.`:"Diferencia contra la categoría recomendada para ese período."}</p>'
$text=[regex]::Replace($text,$pattern,$replacement,1)

# If exact old explanatory text remains
$text=$text.Replace(
  '<p>{advancedTariffSummary?.billing_period===dashboardPeriod?`T3/T3A real vs T4 simulada · ${advancedTariffSummary.valued_count} suministro(s) valorizado(s).`:"Diferencia contra la categoría recomendada para ese período."}</p>',
  '<p>{advancedTariffSummary?.billing_period===dashboardPeriod?`Cambio tarifario valorizado · ${dashboardTariffValuedCount} suministro(s) · incluye T3/T3A→T4 y BT→MT.`:"Diferencia contra la categoría recomendada para ese período."}</p>'
)

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - V19 aplicada." -ForegroundColor Green
Write-Host ""
Write-Host "El resumen general ahora suma:" -ForegroundColor Yellow
Write-Host "  - filas valorizadas de tariff-saving-summary"
Write-Host "  - BT->MT faltantes usando epenOptimization.mt"
Write-Host "  - T4 faltantes usando epenOptimization.t4"
Write-Host "  - sin duplicar medidores ya incluidos en el resumen avanzado"
Write-Host ""
Write-Host "Para medidor 502105395 debería sumar ~15,6 M/mes al Cambio tarifario."
Write-Host "Backup: $backup"
