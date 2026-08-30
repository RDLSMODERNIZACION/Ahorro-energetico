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
$backup="$path.bak-reparacion-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

# ------------------------------------------------------------------
# 1) Asegurar import de useEffect
# ------------------------------------------------------------------
if($text -match 'import \{([^}]*)\} from "react";'){
  $whole=$Matches[0]
  $inside=$Matches[1]
  if($inside -notmatch '\buseEffect\b'){
    $newInside=($inside.Trim()+', useEffect')
    $text=$text.Replace($whole,'import {'+$newInside+'} from "react";')
  }
}

# ------------------------------------------------------------------
# 2) Asegurar tipos del histórico T4
# ------------------------------------------------------------------
if($text -notmatch 'type AdvancedTariffHistoryPoint'){
  $marker='type Metric='
  $idx=$text.IndexOf($marker)
  if($idx -lt 0){throw "No encontré type Metric."}
$typeBlock=@'
type AdvancedTariffHistoryPoint={
  billing_period:string;
  current_tariff:string;
  recommended_tariff:string;
  current_cost:number;
  recommended_cost:number;
  monthly_saving:number;
  annualized_saving:number;
  capacity_kw:number;
};
type AdvancedTariffHistoryResponse={
  meter_id:string;
  mode:"t4"|"none";
  current_tariff?:string;
  recommended_tariff?:string;
  taxes_included?:boolean;
  points:AdvancedTariffHistoryPoint[];
};

'@
  $text=$text.Insert($idx,$typeBlock)
}

# ------------------------------------------------------------------
# 3) Asegurar estado advancedTariffHistory
# ------------------------------------------------------------------
$metricState='const[metric,setMetric]=useState<Metric>("kwh");'
if(-not $text.Contains($metricState)){
  throw "No encontré const[metric,setMetric] en InvoiceAnalysisPanel."
}
if($text -notmatch 'const\[advancedTariffHistory,setAdvancedTariffHistory\]'){
  $text=$text.Replace(
    $metricState,
    $metricState+"`r`n"+'  const[advancedTariffHistory,setAdvancedTariffHistory]=useState<AdvancedTariffHistoryResponse|null>(null);'
  )
}

# ------------------------------------------------------------------
# 4) Asegurar fetch del histórico avanzado
# ------------------------------------------------------------------
if($text -notmatch '/tariff-saving-history'){
  $saveMarker='  async function saveMeterName(){'
  if(-not $text.Contains($saveMarker)){throw "No encontré saveMeterName."}
$effect=@'
  useEffect(()=>{
    let cancelled=false;
    async function loadTariffHistory(){
      try{
        const{data}=await supabase.auth.getSession();
        if(!data.session||!selected.meter_id)return;
        const response=await fetch(`${API}/api/meters/${selected.meter_id}/tariff-saving-history`,{
          cache:"no-store",
          headers:{Authorization:`Bearer ${data.session.access_token}`}
        });
        if(!response.ok)throw new Error(await response.text());
        const json=await response.json() as AdvancedTariffHistoryResponse;
        if(!cancelled)setAdvancedTariffHistory(json);
      }catch{
        if(!cancelled)setAdvancedTariffHistory(null);
      }
    }
    loadTariffHistory();
    return()=>{cancelled=true};
  },[selected.meter_id]);

'@
  $text=$text.Replace($saveMarker,$effect+$saveMarker)
}

# ------------------------------------------------------------------
# 5) Reemplazar COMPLETO el bloque Evolución histórica.
#    Esto elimina cualquier JSX roto generado por V6/V7.
# ------------------------------------------------------------------
$startMarker='      <section className="invoice-analysis-panel">'+"`r`n"+'        <div className="invoice-analysis-chart-head">'
$start=$text.IndexOf($startMarker)

if($start -lt 0){
  # Variante LF
  $startMarker='      <section className="invoice-analysis-panel">'+"`n"+'        <div className="invoice-analysis-chart-head">'
  $start=$text.IndexOf($startMarker)
}
if($start -lt 0){throw "No encontré el inicio del bloque Evolución histórica."}

$nextMarker='      <div className="invoice-analysis-grid">'
$next=$text.IndexOf($nextMarker,$start)
if($next -lt 0){throw "No encontré invoice-analysis-grid después del gráfico."}

$chartBlock=@'
      <section className="invoice-analysis-panel">
        <div className="invoice-analysis-chart-head">
          <div>
            <h3>Evolución histórica del medidor</h3>
            <p>Hasta 24 meses. Tocá una barra para abrir esa factura.</p>
          </div>
          <div className="invoice-analysis-metrics">
            <button className={metric==="kwh"?"active":""} onClick={()=>setMetric("kwh")}>Consumo</button>
            <button className={metric==="amount"?"active":""} onClick={()=>setMetric("amount")}>Importe</button>
            <button className={metric==="demand"?"active":""} onClick={()=>setMetric("demand")}>Demanda</button>
            <button className={metric==="pf"?"active":""} onClick={()=>setMetric("pf")}>Factor potencia</button>
            <button className={metric==="tariff"?"active":""} onClick={()=>setMetric("tariff")}>Ahorro tarifario</button>
          </div>
        </div>

        {metric==="tariff" ? (() => {
          const legacyRows=tariffSavings
            .filter(x=>x.meter_id===selected.meter_id)
            .map(x=>({
              billing_period:String(x.billing_period).slice(0,7),
              monthly_saving:Number(x.monthly_saving_with_vat||0),
              current_tariff:x.current_tariff,
              recommended_tariff:x.recommended_tariff
            }));

          const advancedRows=(advancedTariffHistory?.points||[]).map(x=>({
            billing_period:String(x.billing_period).slice(0,7),
            monthly_saving:Number(x.monthly_saving||0),
            current_tariff:x.current_tariff,
            recommended_tariff:x.recommended_tariff
          }));

          const chartRows=advancedRows.some(x=>x.monthly_saving>0) ? advancedRows : legacyRows;
          const selectedRow=chartRows.find(x=>x.billing_period===periodOf(selected));

          return <div className="invoice-tariff-chart-view">
            <TariffSavingTrend
              rows={chartRows}
              selectedPeriod={periodOf(selected)}
              onPeriod={setSelectedPeriod}
            />
            {selectedRow&&<div className="invoice-tariff-selected-caption">
              <span>{selectedRow.current_tariff||selected.current_tariff_code||"Actual"} → {selectedRow.recommended_tariff||"Propuesta"}</span>
              <b>{money.format(Number(selectedRow.monthly_saving||0))} de ahorro en {periodOf(selected)}</b>
              {advancedRows.some(x=>x.monthly_saving>0)&&<small>Simulación antes de impuestos · T4 requiere contrato EPEN</small>}
            </div>}
          </div>;
        })() : (
          <InvoiceTrend
            rows={sorted}
            metric={metric}
            selectedPeriod={periodOf(selected)}
            onPeriod={setSelectedPeriod}
          />
        )}
      </section>

'@

$text=$text.Substring(0,$start)+$chartBlock+$text.Substring($next)

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - bloque Evolución histórica reconstruido desde cero." -ForegroundColor Green
Write-Host "Se eliminó el JSX roto de las V6/V7." -ForegroundColor Yellow
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Ahora probá:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
