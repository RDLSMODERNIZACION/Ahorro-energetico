from fastapi import APIRouter,Depends,HTTPException,Query
from ..auth import CurrentUser,current_user,require_org
from ..db import admin_db

router=APIRouter(tags=["Facturas"])

@router.get("/organizations/{organization_id}/invoices")
def invoices(organization_id:str,meter_id:str|None=None,limit:int=Query(100,ge=1,le=500),user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id);q=admin_db().table("invoices").select("*,meters(id,meter_number,nis,tracking_code,supply_number,contract_number,service_code,service_name,cadastral_number,current_tariff_code,voltage_level,contracted_kw_peak,contracted_kw_off_peak,sites(name,address)),invoice_measurements(*),invoice_lines(concept_code,description,quantity,unit_price,net_amount)").eq("organization_id",organization_id)
    if meter_id:q=q.eq("meter_id",meter_id)
    return q.order("period_start",desc=True).limit(limit).execute().data

@router.get("/invoices/{invoice_id}")
def invoice(invoice_id:str,user:CurrentUser=Depends(current_user)):
    data=admin_db().table("invoices").select("*,meters(*,sites(*)),invoice_measurements(*),invoice_lines(*)").eq("id",invoice_id).limit(1).execute().data
    if not data:raise HTTPException(404,"Factura inexistente")
    require_org(user.id,data[0]["organization_id"]);return data[0]

@router.delete("/invoices/{invoice_id}",status_code=204)
def delete_invoice(invoice_id:str,user:CurrentUser=Depends(current_user)):
    data=admin_db().table("invoices").select("organization_id").eq("id",invoice_id).limit(1).execute().data
    if not data:raise HTTPException(404,"Factura inexistente")
    require_org(user.id,data[0]["organization_id"],write=True);admin_db().table("invoices").delete().eq("id",invoice_id).execute()
