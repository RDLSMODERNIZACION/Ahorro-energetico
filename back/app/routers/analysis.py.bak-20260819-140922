from collections import defaultdict
from decimal import Decimal
from statistics import median
from fastapi import APIRouter,Depends
from ..auth import CurrentUser,current_user,require_org
from ..db import admin_db

router=APIRouter(tags=["Análisis"])
VAT_FACTOR=Decimal("1.30")

def _num(value):
    try:return Decimal(str(value or 0))
    except:return Decimal(0)

def _metrics(invoice):
    measurements=invoice.get("invoice_measurements") or []
    active=sum(_num(x.get("active_energy_kwh")) for x in measurements)
    demand=max([max(_num(x.get("demand_kw")),_num(x.get("registered_demand_peak_kw"))) for x in measurements] or [Decimal(0)])
    pf=[_num(x.get("power_factor")) for x in measurements if _num(x.get("power_factor"))>0]
    return active,demand,min(pf) if pf else None

def _power_excess_saving(lines):
    excess=[x for x in (lines or []) if x.get("concept_code")=="EXC"]
    units=sum(_num(x.get("quantity")) for x in excess)
    rate=max([_num(x.get("unit_price")) for x in excess if _num(x.get("unit_price"))>0] or [Decimal(0)])
    saving=sum((_num(x.get("quantity"))*_num(x.get("unit_price")) if _num(x.get("quantity"))>0 and _num(x.get("unit_price"))>0 else _num(x.get("net_amount"))) for x in excess).quantize(Decimal("0.01"))
    return units,rate,saving

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

def _voltage_key(value):
    value=(value or "").upper()
    if value in ("BT","BAJA","BAJA TENSION","BAJA TENSIÓN"):return "BT"
    if value in ("MT","MEDIA","MEDIA TENSION","MEDIA TENSIÓN"):return "MT"
    if value in ("AT","ALTA","ALTA TENSION","ALTA TENSIÓN"):return "AT"
    return "NA"

def _official_simulation(rows,period,tariff,voltage,active,capacity_peak,capacity_off_peak,measurements,enforce_limits=True):
    period=str(period or "")[:10];tariff=_tariff_key(tariff);voltage=_voltage_key(voltage)
    applicable=[];schedule=None
    for row in rows:
        category=row.get("tariff_categories") or {};calendar=row.get("tariff_schedules") or {}
        if _tariff_key(category.get("code"))!=tariff:continue
        billing_month=str(calendar.get("billing_month") or "")[:7]
        valid_from=str(calendar.get("valid_from") or calendar.get("consumption_month") or "")[:10]
        valid_to=str(calendar.get("valid_to") or valid_from)[:10]
        if billing_month:
            if not period or str(period)[:7]!=billing_month:continue
        elif not period or not valid_from or not (valid_from<=period<=valid_to):continue
        row_voltage=_voltage_key(row.get("voltage_level"))
        if row_voltage not in ("NA",voltage):continue
        min_kw=_num(row.get("min_capacity_kw"));max_kw=row.get("max_capacity_kw")
        min_kwh=_num(row.get("min_consumption_kwh"));max_kwh=row.get("max_consumption_kwh")
        if enforce_limits and (capacity_peak<min_kw or (max_kw is not None and capacity_peak>=_num(max_kw))):continue
        if enforce_limits and (active<min_kwh or (max_kwh is not None and active>_num(max_kwh))):continue
        applicable.append(row);schedule=calendar
    if not applicable:return None,None
    rates={x.get("charge_code"):_num(x.get("unit_price")) for x in applicable}
    cost=rates.get("CFI",Decimal(0))
    cost+=rates.get("DEM",Decimal(0))*capacity_peak
    cost+=rates.get("DEP",Decimal(0))*capacity_peak
    cost+=rates.get("DFP",Decimal(0))*(capacity_off_peak or capacity_peak)
    bands=defaultdict(Decimal)
    for m in measurements:bands[m.get("time_band") or "all"]+=_num(m.get("active_energy_kwh"))
    if any(code in rates for code in ("EPI","ERE","EVA")):
        band_total=bands["peak"]+bands["remaining"]+bands["valley"]
        if band_total:
            cost+=bands["peak"]*rates.get("EPI",Decimal(0))+bands["remaining"]*rates.get("ERE",Decimal(0))+bands["valley"]*rates.get("EVA",Decimal(0))
        else:
            energy=[rates[x] for x in ("EPI","ERE","EVA") if x in rates]
            if energy:cost+=active*(sum(energy)/len(energy))
    else:cost+=active*rates.get("ECO",Decimal(0))
    return cost.quantize(Decimal("0.01")),schedule

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
    official_rates=db.table("tariff_rates").select("unit_price,voltage_level,customer_segment,min_capacity_kw,max_capacity_kw,min_consumption_kwh,max_consumption_kwh,charge_code,time_band,tariff_categories(code),tariff_schedules(resolution_number,consumption_month,billing_month,valid_from,valid_to,excludes_taxes)").execute().data
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
        contracted=_num(latest.get("contracted_kw_peak"));contracted_off_peak=_num(latest.get("contracted_kw_off_peak"))
        lines=latest.get("invoice_lines") or []
        billed_capacity=max([_num(x.get("quantity")) for x in lines if x.get("concept_code") in ("DEM","DEP") and _num(x.get("quantity"))>0] or [Decimal(0)])
        capacity=contracted or billed_capacity or max_demand
        current=_tariff_key(latest.get("current_tariff_code") or meter.get("current_tariff_code"))
        # Escenario de ahorro máximo solicitado: contratar exactamente la mayor
        # potencia registrada, sin reserva ni margen adicional.
        recommended=max_demand
        expected=_expected_tariff(recommended,active,current)
        correctly_framed=current==expected
        excess_units,excess_rate,excess_saving=_power_excess_saving(lines)
        power_rate=max([_num(x.get("unit_price")) for x in lines if x.get("concept_code") in ("DEM","DEP") and _num(x.get("unit_price"))>0] or [Decimal(0)])
        reducible=max(Decimal(0),capacity-recommended)
        monthly_power_saving=(reducible*power_rate*VAT_FACTOR).quantize(Decimal("0.01"))
        reactive_saving=(max(Decimal(0),sum(_num(x.get("net_amount")) for x in lines if x.get("concept_code")=="COS"))*VAT_FACTOR).quantize(Decimal("0.01"))
        period=latest.get("billing_period") or latest.get("period_start")
        official_current,current_schedule=_official_simulation(official_rates,period,current,latest.get("voltage_level"),active,capacity,contracted_off_peak,latest.get("invoice_measurements") or [],enforce_limits=False)
        official_current_adjusted,_=_official_simulation(official_rates,period,current,latest.get("voltage_level"),active,recommended,recommended,latest.get("invoice_measurements") or [],enforce_limits=False)
        official_simulated,schedule=_official_simulation(official_rates,period,expected,latest.get("voltage_level"),active,recommended,recommended,latest.get("invoice_measurements") or [])
        official_available=official_current_adjusted is not None and official_simulated is not None
        price_source="official" if official_available else None
        if official_current_adjusted is not None:official_current_adjusted=(official_current_adjusted*VAT_FACTOR).quantize(Decimal("0.01"))
        if official_simulated is not None:official_simulated=(official_simulated*VAT_FACTOR).quantize(Decimal("0.01"))
        monthly_tariff_saving=max(Decimal(0),official_current_adjusted-official_simulated).quantize(Decimal("0.01")) if not correctly_framed and official_available else Decimal(0)
        monthly_total=monthly_power_saving+reactive_saving+monthly_tariff_saving
        reasons=[]
        if not correctly_framed:
            if official_available:reasons.append(f"Segun el cuadro EPEN {schedule.get('resolution_number')} vigente para el periodo, corresponde {expected} y no {current}; con {recommended} kW el costo en {current} seria ${official_current_adjusted} y en {expected} ${official_simulated}")
            else:reasons.append(f"La capacidad de {capacity} kW corresponde a {expected}; falta el cuadro oficial vigente de una de las categorias para valorizar el cambio")
        if reducible>0:reasons.append(f"La demanda máxima observada fue {max_demand} kW frente a {capacity} kW contratados; se valorizan {reducible} kW de más a ${power_rate} por kW más 30% de IVA")
        if reactive_saving>0:reasons.append(f"El recargo COS evitable, incluido 30% de IVA, es ${reactive_saving}")
        elif pf is not None and pf<Decimal("0.95"):reasons.append(f"Factor de potencia bajo: {pf}")
        confidence=90 if len(history)>=6 else 75 if len(history)>=3 else 45
        status="change_candidate" if not correctly_framed else "power_review" if reducible>0 or reactive_saving>0 else "correct"
        if len(history)<3 and status!="correct":status="provisional"
        correct_reason=f"Tarifa {current} correcta segun el cuadro EPEN {schedule.get('resolution_number')} vigente para el periodo" if schedule else "El encuadramiento coincide con la capacidad declarada; falta el cuadro oficial de ese periodo para validar precios"
        result.append({"meter_id":meter_id,"meter":meter,"current_tariff":latest.get("current_tariff_code"),"recommended_tariff":expected,"status":status,"reasons":reasons or [correct_reason],"periods_analyzed":len(history),"billing_period":latest.get("billing_period"),"consumption_kwh":float(active),"maximum_demand_kw":float(max_demand),"contracted_kw":float(capacity),"recommended_kw":float(recommended),"power_factor":float(pf) if pf is not None else None,"power_excess_kw":float(reducible),"power_unit_price":float(power_rate),"power_saving_source":"contracted_reduction" if monthly_power_saving>0 else None,"power_monthly_saving":float(monthly_power_saving),"power_annual_saving":float(monthly_power_saving*12),"reactive_monthly_saving":float(reactive_saving),"reactive_annual_saving":float(reactive_saving*12),"tariff_current_simulated":float(official_current_adjusted) if official_current_adjusted is not None else None,"tariff_recommended_simulated":float(official_simulated) if official_simulated is not None else None,"tariff_monthly_saving":float(monthly_tariff_saving),"tariff_annual_saving":float(monthly_tariff_saving*12),"tariff_simulation_available":official_available,"tariff_price_source":price_source,"official_schedule":schedule or current_schedule,"estimated_monthly_saving":float(monthly_total),"estimated_annual_saving":float(monthly_total*12),"confidence":confidence,"requires_epen_review":not correctly_framed or reducible>0 or reactive_saving>0,"vat_percent":30})
    return sorted(result,key=lambda x:(x["status"]=="correct",-x["estimated_annual_saving"]))

@router.post("/organizations/{organization_id}/analysis/run")
def run_analysis(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id,write=True);db=admin_db()
    invoices=db.table("invoices").select("id,meter_id,total_amount,contracted_kw_peak,current_tariff_code,invoice_measurements(*),invoice_lines(concept_code,quantity,unit_price,net_amount)").eq("organization_id",organization_id).execute().data
    db.table("opportunities").delete().eq("organization_id",organization_id).eq("status","detected").execute(); created=[]
    for inv in invoices:
        measurements=inv.get("invoice_measurements") or []; demand=max([Decimal(str(x.get("demand_kw") or 0)) for x in measurements] or [Decimal(0)])
        lines=inv.get("invoice_lines") or []
        contracted=Decimal(str(inv.get("contracted_kw_peak") or 0))
        billed_capacity=max([_num(x.get("quantity")) for x in lines if x.get("concept_code") in ("DEM","DEP") and _num(x.get("quantity"))>0] or [Decimal(0)])
        capacity=contracted or billed_capacity
        power_rate=max([_num(x.get("unit_price")) for x in lines if x.get("concept_code") in ("DEM","DEP") and _num(x.get("unit_price"))>0] or [Decimal(0)])
        reducible=max(Decimal(0),capacity-demand)
        if reducible>0 and power_rate>0:
            pct=reducible/capacity;monthly=(reducible*power_rate*VAT_FACTOR).quantize(Decimal("0.01"));annual=monthly*12
            created.append({"organization_id":organization_id,"meter_id":inv["meter_id"],"invoice_id":inv["id"],"opportunity_type":"contracted_power","title":"Potencia contratada sobredimensionada","current_value":str(capacity),"recommended_value":str(demand),"estimated_monthly_saving":str(monthly),"estimated_annual_saving":str(annual.quantize(Decimal("0.01"))),"confidence":85,"priority":"high" if pct>Decimal("0.35") else "medium","calculation":{"maximum_demand_kw":str(demand),"unused_capacity_kw":str(reducible),"unit_price":str(power_rate),"vat_percent":30}})
        reactive=sum(Decimal(str(x.get("reactive_energy_kvarh") or 0)) for x in measurements)
        active=sum(Decimal(str(x.get("active_energy_kwh") or 0)) for x in measurements)
        if active>0 and reactive/active>Decimal("0.30"):
            monthly=(sum(_num(x.get("net_amount")) for x in lines if x.get("concept_code")=="COS")*VAT_FACTOR).quantize(Decimal("0.01"))
            if monthly>0:
                annual=monthly*12;created.append({"organization_id":organization_id,"meter_id":inv["meter_id"],"invoice_id":inv["id"],"opportunity_type":"reactive_energy","title":"Revisar compensación de energía reactiva","estimated_monthly_saving":str(monthly),"estimated_annual_saving":str(annual.quantize(Decimal("0.01"))),"confidence":70,"priority":"medium","calculation":{"reactive_active_ratio":str(reactive/active),"vat_percent":30}})
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
