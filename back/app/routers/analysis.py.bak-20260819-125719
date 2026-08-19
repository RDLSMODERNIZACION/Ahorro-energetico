from collections import defaultdict
from decimal import Decimal, ROUND_UP
from statistics import median
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

def _tariff_key(code):
    return (code or "").upper().replace("-","")

def _simulate_tariff(ratebook,period,tariff,voltage,active,capacity,measurements):
    rates=ratebook.get((period,_tariff_key(tariff),voltage or ""))
    if not rates:return None
    cost=Decimal(0)
    for fixed in ("CFI",):
        if fixed in rates:cost+=rates[fixed]
    power_code="DEP" if _tariff_key(tariff) in ("T3","T3A") else "DEM"
    if power_code in rates:cost+=rates[power_code]*capacity
    bands={"peak":Decimal(0),"remaining":Decimal(0),"valley":Decimal(0)}
    for m in measurements:
        band=m.get("time_band") or "all";bands[band]=bands.get(band,Decimal(0))+_num(m.get("active_energy_kwh"))
    if _tariff_key(tariff) in ("T3","T3A") and any(x in rates for x in ("EPI","ERE","EVA")):
        band_total=sum(bands.values())
        if band_total>0:
            cost+=bands.get("peak",0)*rates.get("EPI",Decimal(0))+bands.get("remaining",0)*rates.get("ERE",Decimal(0))+bands.get("valley",0)*rates.get("EVA",Decimal(0))
        else:
            energy_rates=[rates[x] for x in ("EPI","ERE","EVA") if x in rates]
            if energy_rates:cost+=active*(sum(energy_rates)/len(energy_rates))
    elif "ECO" in rates:cost+=active*rates["ECO"]
    if "CAV" in rates:cost+=active*rates["CAV"]
    return cost

@router.get("/organizations/{organization_id}/tariff-assessments")
def tariff_assessments(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id);db=admin_db()
    rows=db.table("invoices").select("id,meter_id,invoice_number,billing_period,period_start,total_amount,net_taxable,current_tariff_code,voltage_level,contracted_kw_peak,contracted_kw_off_peak,meters(id,meter_number,tracking_code,supply_number,contract_number,service_name,current_tariff_code,voltage_level),invoice_measurements(*),invoice_lines(concept_code,quantity,unit_price,net_amount)").eq("organization_id",organization_id).execute().data
    observed=defaultdict(lambda:defaultdict(list))
    for row in rows:
        key=(row.get("billing_period") or row.get("period_start"),_tariff_key(row.get("current_tariff_code")),row.get("voltage_level") or "")
        for line in row.get("invoice_lines") or []:
            code=line.get("concept_code");price=_num(line.get("unit_price"))
            if code=="CFI" and price<=0:price=_num(line.get("net_amount"))
            if code and price>0:observed[key][code].append(price)
    ratebook={key:{code:Decimal(str(median(values))) for code,values in concepts.items()} for key,concepts in observed.items()}
    grouped=defaultdict(list)
    for row in rows:grouped[row["meter_id"]].append(row)
    result=[]
    for meter_id,history in grouped.items():
        history.sort(key=lambda x:x.get("billing_period") or x.get("period_start") or "",reverse=True)
        latest=history[0];meter=latest.get("meters") or {};active,demand,pf=_metrics(latest)
        history_demands=[_metrics(x)[1] for x in history];max_demand=max(history_demands or [Decimal(0)])
        contracted=_num(latest.get("contracted_kw_peak"));capacity=contracted or max_demand
        current=_tariff_key(latest.get("current_tariff_code") or meter.get("current_tariff_code"))
        expected=_expected_tariff(capacity,active,current)
        correctly_framed=current==expected
        safe=(max_demand*Decimal("1.15")).quantize(Decimal("1"),rounding=ROUND_UP) if max_demand else contracted
        floor=Decimal(0) if expected.startswith("T1") else Decimal(10) if expected=="T2" else Decimal(50) if expected=="T3" else Decimal(300)
        recommended=max(safe,floor)
        power_rate=max([_num(x.get("unit_price")) for x in (latest.get("invoice_lines") or []) if x.get("concept_code") in ("DEM","DEP") and _num(x.get("unit_price"))>0] or [Decimal(0)])
        reducible=max(Decimal(0),contracted-recommended)
        monthly_power_saving=(reducible*power_rate).quantize(Decimal("0.01"))
        reactive_saving=sum(_num(x.get("net_amount")) for x in (latest.get("invoice_lines") or []) if x.get("concept_code")=="COS").quantize(Decimal("0.01"))
        period=latest.get("billing_period") or latest.get("period_start")
        simulated=_simulate_tariff(ratebook,period,expected,latest.get("voltage_level"),active,contracted,latest.get("invoice_measurements") or []) if not correctly_framed else None
        current_base=max(Decimal(0),_num(latest.get("net_taxable"))-reactive_saving)
        monthly_tariff_saving=max(Decimal(0),current_base-simulated).quantize(Decimal("0.01")) if simulated is not None else Decimal(0)
        monthly_total=monthly_power_saving+reactive_saving+monthly_tariff_saving
        reasons=[]
        if not correctly_framed:reasons.append(f"La capacidad de {capacity} kW corresponde a {expected}")
        if reducible>0:reasons.append(f"La demanda máxima observada fue {max_demand} kW frente a {contracted} kW contratados")
        if pf is not None and pf<Decimal("0.95"):reasons.append(f"Factor de potencia bajo: {pf}")
        confidence=90 if len(history)>=6 else 75 if len(history)>=3 else 45
        status="change_candidate" if not correctly_framed else "power_review" if reducible>0 else "correct"
        if len(history)<3 and status!="correct":status="provisional"
        result.append({"meter_id":meter_id,"meter":meter,"current_tariff":latest.get("current_tariff_code"),"recommended_tariff":expected,"status":status,"reasons":reasons or ["El encuadramiento coincide con la capacidad declarada"],"periods_analyzed":len(history),"billing_period":latest.get("billing_period"),"consumption_kwh":float(active),"maximum_demand_kw":float(max_demand),"contracted_kw":float(contracted),"recommended_kw":float(recommended),"power_factor":float(pf) if pf is not None else None,"power_monthly_saving":float(monthly_power_saving),"power_annual_saving":float(monthly_power_saving*12),"reactive_monthly_saving":float(reactive_saving),"reactive_annual_saving":float(reactive_saving*12),"tariff_monthly_saving":float(monthly_tariff_saving),"tariff_annual_saving":float(monthly_tariff_saving*12),"tariff_simulation_available":simulated is not None or correctly_framed,"estimated_monthly_saving":float(monthly_total),"estimated_annual_saving":float(monthly_total*12),"confidence":confidence,"requires_epen_review":not correctly_framed or reducible>0})
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
