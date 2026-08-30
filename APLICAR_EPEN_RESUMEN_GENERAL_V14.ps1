$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if ((Test-Path (Join-Path $Root "front\app\page.tsx")) -and (Test-Path (Join-Path $Root "back\app\routers\tariff_history.py"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\page.tsx")) -and (Test-Path (Join-Path $Parent "back\app\routers\tariff_history.py"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$front=Join-Path $Repo "front\app\page.tsx"
$backend=Join-Path $Repo "back\app\routers\tariff_history.py"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_v14_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $front $backup
Copy-Item $backend $backup

# ---------------- BACKEND ----------------
$b=Get-Content $backend -Raw

if($b -notmatch 'tariff-saving-summary'){
$append=@'


@router.get("/organizations/{organization_id}/tariff-saving-summary")
def tariff_saving_summary(
    organization_id: str,
    period: str,
    user: CurrentUser = Depends(current_user),
):
    """
    Resumen general mensual de ahorro tarifario usando la MISMA metodología
    que el análisis individual:
      T3/T3A REAL facturada - T4 simulada.

    Devuelve total mensual y detalle por medidor.
    """
    require_org(user.id, organization_id)
    db = admin_db()

    period = str(period or "")[:7]

    rates = db.table("tariff_rates").select(
        "unit_price,voltage_level,min_capacity_kw,max_capacity_kw,"
        "charge_code,time_band,tariff_categories(code),"
        "tariff_schedules(resolution_number,consumption_month,billing_month,valid_from,valid_to)"
    ).execute().data or []

    invoices = db.table("invoices").select(
        "id,meter_id,billing_period,period_start,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw,"
        "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,"
        "registered_demand_off_peak_kw,time_band),"
        "invoice_lines(concept_code,description,quantity,unit_price,net_amount),"
        "meters(id,meter_number,supply_number,service_name,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw)"
    ).eq("organization_id", organization_id).execute().data or []

    grouped = {}
    for invoice in invoices:
        grouped.setdefault(invoice["meter_id"], []).append(invoice)

    rows = []
    total = Decimal("0")

    for meter_id, history in grouped.items():
        history = _one_invoice_per_period(history)
        if not history:
            continue

        history.sort(key=lambda x: _period(x))
        last12 = [x for x in history if _period(x) <= period][-12:]
        selected = next((x for x in history if _period(x) == period), None)

        if selected is None:
            continue

        meter = selected.get("meters") or {}
        tariff = _tariff_key(selected.get("current_tariff_code") or meter.get("current_tariff_code"))
        voltage = _voltage_key(selected.get("voltage_level") or meter.get("voltage_level"))

        if tariff not in {"T3", "T3A"} or voltage not in {"MT", "AT"}:
            continue

        # Mismo criterio de candidato T4 usado en análisis individual.
        months_over_100 = sum(1 for x in last12 if _max_demand(x) >= Decimal("100"))
        if len(last12) < 12 or months_over_100 != 12:
            continue

        peak_kw, off_kw = _contracted(selected)
        demand = _max_demand(selected)
        if peak_kw <= 0:
            peak_kw = demand

        capacity_kw = max(peak_kw, off_kw, demand)
        target = "T4-MT" if voltage == "MT" else "T4-AT"

        actual_cost, actual_components = _actual_tariff_cost(selected)
        proposed_cost, proposed_components, schedule = _proposed_t4_components(
            rates, selected, target, voltage, capacity_kw
        )

        available = actual_cost is not None and proposed_cost is not None
        saving = Decimal("0")
        if available:
            saving = max(Decimal("0"), actual_cost - proposed_cost)
            total += saving

        rows.append({
            "meter_id": meter_id,
            "meter_number": meter.get("meter_number"),
            "supply_number": meter.get("supply_number"),
            "service_name": meter.get("service_name"),
            "billing_period": period,
            "current_tariff": tariff,
            "recommended_tariff": target,
            "current_cost": None if actual_cost is None else float(actual_cost),
            "recommended_cost": None if proposed_cost is None else float(proposed_cost),
            "monthly_saving": float(saving),
            "annualized_saving": float(saving * 12),
            "capacity_kw": float(capacity_kw),
            "available": available,
            "reason": None if available else (
                "missing_actual_tariff_lines" if actual_cost is None
                else "missing_tariff_schedule"
            ),
            "resolution_number": None if not schedule else schedule.get("resolution_number"),
        })

    return {
        "billing_period": period,
        "monthly_saving": float(total),
        "annualized_saving": float(total * 12),
        "candidate_count": len(rows),
        "valued_count": sum(1 for x in rows if x["available"]),
        "meters": rows,
        "methodology": "actual_current_tariff_cost - simulated_t4_cost",
        "taxes_included": False,
    }
'@
Add-Content $backend $append -Encoding UTF8
}

# ---------------- FRONT ----------------
$f=Get-Content $front -Raw

# Types
if($f -notmatch 'type AdvancedTariffSummary'){
$type=@'
type AdvancedTariffSummaryMeter={meter_id:string;billing_period:string;current_tariff:string;recommended_tariff:string;monthly_saving:number;annualized_saving:number;available:boolean;resolution_number?:string|null};
type AdvancedTariffSummary={billing_period:string;monthly_saving:number;annualized_saving:number;candidate_count:number;valued_count:number;meters:AdvancedTariffSummaryMeter[]};

'@
$marker='type TariffSavingResponse'
$idx=$f.IndexOf($marker)
if($idx -lt 0){throw "No encontré TariffSavingResponse."}
$f=$f.Insert($idx,$type)
}

# State
if($f -notmatch 'advancedTariffSummary'){
$stateNeedle='const[epenOptimization,setEpenOptimization]=useState<EpenOptimizationMeter[]>([]);'
if(-not $f.Contains($stateNeedle)){throw "No encontré estado epenOptimization."}
$f=$f.Replace($stateNeedle,$stateNeedle+"`r`n"+'  const[advancedTariffSummary,setAdvancedTariffSummary]=useState<AdvancedTariffSummary|null>(null);')
}

# Replace dashboardRateMonthly formula
$oldRate='const dashboardRateMonthly=tariffSavings.filter(x=>String(x.billing_period).slice(0,7)===dashboardPeriod).reduce((sum,x)=>sum+Number(x.monthly_saving_with_vat||0),0);'
$newRate=@'
const legacyDashboardRateMonthly=tariffSavings.filter(x=>String(x.billing_period).slice(0,7)===dashboardPeriod).reduce((sum,x)=>sum+Number(x.monthly_saving_with_vat||0),0);
  const dashboardRateMonthly=advancedTariffSummary?.billing_period===dashboardPeriod
    ?Number(advancedTariffSummary.monthly_saving||0)
    :legacyDashboardRateMonthly;
'@
if($f.Contains($oldRate)){
  $f=$f.Replace($oldRate,$newRate)
}elseif($f -notmatch 'legacyDashboardRateMonthly'){
  throw "No encontré dashboardRateMonthly actual."
}

# hasTariff in opportunity count
$oldHas='const hasTariff=tariffSavings.some(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===dashboardPeriod&&Number(x.monthly_saving_with_vat||0)>0);'
$newHas='const hasTariff=(advancedTariffSummary?.billing_period===dashboardPeriod?advancedTariffSummary.meters.some(x=>x.meter_id===i.meter_id&&x.available&&Number(x.monthly_saving||0)>0):tariffSavings.some(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===dashboardPeriod&&Number(x.monthly_saving_with_vat||0)>0));'
if($f.Contains($oldHas)){$f=$f.Replace($oldHas,$newHas)}

# Load summary effect. Insert before login function, after existing load effects.
if($f -notmatch '/tariff-saving-summary'){
$loginMarker='  async function login(e:FormEvent)'
$idx=$f.IndexOf($loginMarker)
if($idx -lt 0){throw "No encontré login()."}

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
$f=$f.Insert($idx,$effect)
}

# Card description: make methodology explicit
$f=$f.Replace(
  '<p>Diferencia contra la categoría recomendada para ese período.</p>',
  '<p>{advancedTariffSummary?.billing_period===dashboardPeriod?"T3/T3A real facturada vs T4 simulada para ese período.":"Diferencia contra la categoría recomendada para ese período."}</p>'
)

Set-Content $front $f -Encoding UTF8

Write-Host ""
Write-Host "OK - V14 aplicada." -ForegroundColor Green
Write-Host "El resumen general ahora toma el ahorro tarifario avanzado:" -ForegroundColor Yellow
Write-Host "  - T3/T3A real facturada"
Write-Host "  - menos T4 simulada"
Write-Host "  - mismo período del dashboard"
Write-Host "  - suma todos los medidores candidatos valorizados"
Write-Host ""
Write-Host "IMPORTANTE: desplegar backend en Render."
Write-Host "Backup: $backup"
