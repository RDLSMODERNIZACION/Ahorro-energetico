from collections import defaultdict
from decimal import Decimal
from fastapi import APIRouter,Depends
from ..auth import CurrentUser,current_user,require_org
from ..db import admin_db

router=APIRouter(tags=["Análisis"])

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
