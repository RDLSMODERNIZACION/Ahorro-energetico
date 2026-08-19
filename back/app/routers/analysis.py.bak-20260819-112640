from collections import defaultdict
from decimal import Decimal, ROUND_UP
from fastapi import APIRouter,Depends
from ..auth import CurrentUser,current_user,require_org
from ..db import admin_db

router=APIRouter(tags=["Análisis"])

def _num(value):
    try:return Decimal(str(value or 0))
    except:return Decimal(0)

def _metrics(invoice):
    measurements=invoice.get("invoice_measurements") or []
    active=sum(_num(x.get("active_energy_kwh")) for x in measurements)
    demand=max([max(_num(x.get("demand_kw")),_num(x.get("registered_demand_peak_kw"))) for x in measurements] or [Decimal(0)])
    pf=[_num(x.get("power_factor")) for x in measurements if _num(x.get("power_factor"))>0]
    return active,demand,min(pf) if pf else None

def _expected_tariff(capacity,consumption,current=""):
    if current.upper().startswith("RN"):
        if consumption <= 50:return "RN11"
        if consumption <= 100:return "RN12"
        if consumption <= 250:return "RN13"
        if consumption <= 500:return "RN14"
        if consumption <= 700:return "RN15"
        if consumption <= 1400:return "RN16"
        return "RN17"
    if capacity < 10:
        if consumption <= 250:return "T1G"
        if consumption <= 1000:return "T1G2"
        if consumption <= 2000:return "T1G3"
        return "T1G4"
    if capacity < 50:return "T2"
    if capacity < 300:return "T3"
    return "T3A"

@router.get("/organizations/{organization_id}/tariff-assessments")
def tariff_assessments(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id);db=admin_db()
    rows=db.table("invoices").select("id,meter_id,invoice_number,billing_period,period_start,total_amount,current_tariff_code,voltage_level,contracted_kw_peak,contracted_kw_off_peak,meters(id,meter_number,tracking_code,supply_number,contract_number,service_name,current_tariff_code,voltage_level),invoice_measurements(*),invoice_lines(concept_code,quantity,unit_price,net_amount)").eq("organization_id",organization_id).execute().data
    grouped=defaultdict(list)
    for row in rows:grouped[row["meter_id"]].append(row)
    result=[]
    for meter_id,history in grouped.items():
        history.sort(key=lambda x:x.get("billing_period") or x.get("period_start") or "",reverse=True)
        latest=history[0];meter=latest.get("meters") or {};active,demand,pf=_metrics(latest)
        history_demands=[_metrics(x)[1] for x in history];max_demand=max(history_demands or [Decimal(0)])
        contracted=_num(latest.get("contracted_kw_peak"));capacity=contracted or max_demand
        current=(latest.get("current_tariff_code") or meter.get("current_tariff_code") or "").upper().replace("-","")
        expected=_expected_tariff(capacity,active,current)
        correctly_framed=current==expected
        safe=(max_demand*Decimal("1.15")).quantize(Decimal("1"),rounding=ROUND_UP) if max_demand else contracted
        floor=Decimal(0) if expected.startswith("T1") else Decimal(10) if expected=="T2" else Decimal(50) if expected=="T3" else Decimal(300)
        recommended=max(safe,floor)
        power_rate=max([_num(x.get("unit_price")) for x in (latest.get("invoice_lines") or []) if x.get("concept_code") in ("DEM","DEP") and _num(x.get("unit_price"))>0] or [Decimal(0)])
        reducible=max(Decimal(0),contracted-recommended)
        monthly_power_saving=(reducible*power_rate).quantize(Decimal("0.01"))
        reasons=[]
        if not correctly_framed:reasons.append(f"La capacidad de {capacity} kW corresponde a {expected}")
        if reducible>0:reasons.append(f"La demanda máxima observada fue {max_demand} kW frente a {contracted} kW contratados")
        if pf is not None and pf<Decimal("0.95"):reasons.append(f"Factor de potencia bajo: {pf}")
        confidence=90 if len(history)>=6 else 75 if len(history)>=3 else 45
        status="change_candidate" if not correctly_framed else "power_review" if reducible>0 else "correct"
        if len(history)<3 and status!="correct":status="provisional"
        result.append({"meter_id":meter_id,"meter":meter,"current_tariff":latest.get("current_tariff_code"),"recommended_tariff":expected,"status":status,"reasons":reasons or ["El encuadramiento coincide con la capacidad declarada"],"periods_analyzed":len(history),"billing_period":latest.get("billing_period"),"consumption_kwh":float(active),"maximum_demand_kw":float(max_demand),"contracted_kw":float(contracted),"recommended_kw":float(recommended),"power_factor":float(pf) if pf is not None else None,"estimated_monthly_saving":float(monthly_power_saving),"estimated_annual_saving":float(monthly_power_saving*12),"confidence":confidence,"requires_epen_review":not correctly_framed or reducible>0})
    return sorted(result,key=lambda x:(x["status"]=="correct",-x["estimated_annual_saving"]))

@router.post("/organizations/{organization_id}/analysis/run")
def run_analysis(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id,write=True);db=admin_db()
    invoices=db.table("invoices").select("id,meter_id,total_amount,contracted_kw_peak,current_tariff_code,invoice_measurements(*)").eq("organization_id",organization_id).execute().data
    db.table("opportunities").delete().eq("organization_id",organization_id).eq("status","detected").execute(); created=[]
    for inv in invoices:
        measurements=inv.get("invoice_measurements") or []; demand=max([Decimal(str(x.get("demand_kw") or 0)) for x in measurements] or [Decimal(0)])
        contracted=Decimal(str(inv.get("contracted_kw_peak") or 0));amount=Decimal(str(inv.get("total_amount") or 0))
        if contracted>0 and demand/contracted<Decimal("0.75"):
            pct=(contracted-demand)/contracted;annual=amount*Decimal(12)*min(pct*Decimal("0.30"),Decimal("0.18"))
            created.append({"organization_id":organization_id,"meter_id":inv["meter_id"],"invoice_id":inv["id"],"opportunity_type":"contracted_power","title":"Potencia contratada sobredimensionada","current_value":str(contracted),"recommended_value":str((demand*Decimal("1.15")).quantize(Decimal("0.1"))),"estimated_monthly_saving":str((annual/12).quantize(Decimal("0.01"))),"estimated_annual_saving":str(annual.quantize(Decimal("0.01"))),"confidence":85,"priority":"high" if pct>Decimal("0.35") else "medium","calculation":{"maximum_demand_kw":str(demand),"unused_capacity_ratio":str(pct)}})
        reactive=sum(Decimal(str(x.get("reactive_energy_kvarh") or 0)) for x in measurements)
        active=sum(Decimal(str(x.get("active_energy_kwh") or 0)) for x in measurements)
        if active>0 and reactive/active>Decimal("0.30"):
            annual=amount*Decimal("0.05")*12;created.append({"organization_id":organization_id,"meter_id":inv["meter_id"],"invoice_id":inv["id"],"opportunity_type":"reactive_energy","title":"Revisar compensación de energía reactiva","estimated_monthly_saving":str((annual/12).quantize(Decimal("0.01"))),"estimated_annual_saving":str(annual.quantize(Decimal("0.01"))),"confidence":70,"priority":"medium","calculation":{"reactive_active_ratio":str(reactive/active)}})
    if created:db.table("opportunities").insert(created).execute()
    return {"analyzed_invoices":len(invoices),"opportunities_created":len(created)}

@router.get("/organizations/{organization_id}/opportunities")
def opportunities(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id)
    return admin_db().table("opportunities").select("*,meters(meter_number,sites(name))").eq("organization_id",organization_id).order("estimated_annual_saving",desc=True).execute().data

@router.get("/organizations/{organization_id}/dashboard")
def dashboard(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id);db=admin_db();inv=db.table("invoices").select("total_amount,invoice_measurements(active_energy_kwh)").eq("organization_id",organization_id).execute().data;opp=db.table("opportunities").select("estimated_annual_saving,status").eq("organization_id",organization_id).execute().data
    return {"invoice_count":len(inv),"total_billed":sum(float(x.get("total_amount") or 0) for x in inv),"total_kwh":sum(float(m.get("active_energy_kwh") or 0) for x in inv for m in (x.get("invoice_measurements") or [])),"active_opportunities":len([x for x in opp if x["status"] not in ("dismissed","implemented")]),"annual_saving_potential":sum(float(x.get("estimated_annual_saving") or 0) for x in opp if x["status"]!="dismissed")}
