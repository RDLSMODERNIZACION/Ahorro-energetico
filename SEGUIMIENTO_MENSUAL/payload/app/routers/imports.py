import hashlib
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from ..auth import CurrentUser, current_user, require_org
from ..config import get_settings
from ..db import admin_db
from ..importer import import_invoices

router=APIRouter(tags=["Importaciones"])

@router.post("/imports/invoices")
async def upload_invoices(organization_id: str=Form(...), file: UploadFile=File(...), user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id,write=True)
    payload=await file.read(); limit=get_settings().max_upload_mb*1024*1024
    if len(payload)>limit: raise HTTPException(413,f"El archivo supera {get_settings().max_upload_mb} MB")
    return import_invoices(organization_id,user.id,file.filename or "facturas.zip",payload)

@router.post("/imports/document")
async def upload_document(organization_id:str=Form(...),folder:str=Form("invoices"),file:UploadFile=File(...),user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id,write=True); payload=await file.read()
    digest=hashlib.sha256(payload).hexdigest(); safe=(file.filename or "documento").replace("/","_").replace("\\","_")
    path=f"{organization_id}/{folder}/{digest[:12]}-{safe}"
    admin_db().storage.from_("energy-documents").upload(path,payload,{"content-type":file.content_type or "application/octet-stream","upsert":"false"})
    return {"path":path,"sha256":digest,"size":len(payload)}

@router.get("/organizations/{organization_id}/imports")
def batches(organization_id:str,user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id)
    return admin_db().table("import_batches").select("*").eq("organization_id",organization_id).order("created_at",desc=True).execute().data

@router.get("/organizations/{organization_id}/missing-invoices")
def missing_invoices(organization_id:str,status:str="open",user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id)
    query=admin_db().table("missing_invoice_alerts").select("*,meters(tracking_code,meter_number,nis,sites(name))").eq("organization_id",organization_id)
    if status != "all": query=query.eq("status",status)
    return query.order("expected_period",desc=True).execute().data
