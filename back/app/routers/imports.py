import hashlib
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from ..auth import CurrentUser, current_user, require_org
from ..config import get_settings
from ..db import admin_db
from ..importer import import_invoices
from ..energy_intelligence import refresh_energy_intelligence
from ..pdf_import_jobs import start_job, run_job
from ..pdf_invoices import documents
from starlette.concurrency import run_in_threadpool

router=APIRouter(tags=["Importaciones"])

@router.post("/imports/invoices")
async def upload_invoices(background_tasks: BackgroundTasks, organization_id: str=Form(...), file: UploadFile=File(...), user:CurrentUser=Depends(current_user)):
    require_org(user.id,organization_id,write=True)
    limit=get_settings().max_upload_mb*1024*1024; payload=await file.read(limit+1)
    if len(payload)>limit: raise HTTPException(413,f"El archivo supera {get_settings().max_upload_mb} MB")
    filename = file.filename or "facturas.pdf"
    try:
        # ZIP with CSV remains compatible with the original importer.
        entries = await run_in_threadpool(documents, payload, filename)
        if all(name.lower().endswith('.csv') for name, _ in entries):
            if filename.lower().endswith('.rar'):
                raise ValueError('Para CSV usá un archivo CSV o ZIP')
            result = await run_in_threadpool(import_invoices, organization_id, user.id, filename, payload)
            background_tasks.add_task(refresh_energy_intelligence, organization_id)
            return result
        batch_id, launch = await run_in_threadpool(start_job, organization_id, user.id, filename, payload)
    except (ValueError, OSError) as exc:
        raise HTTPException(400, str(exc)) from exc
    except Exception as exc:
        import zipfile
        if isinstance(exc, zipfile.BadZipFile):
            raise HTTPException(400, 'El ZIP está dañado') from exc
        raise
    if launch:
        background_tasks.add_task(run_job, batch_id, organization_id, filename, payload)
    return {"batch_id":batch_id,"status":"processing","background":True}

@router.get("/imports/invoices/{batch_id}")
def invoice_import_status(batch_id: str, user:CurrentUser=Depends(current_user)):
    batch = admin_db().table("import_batches").select("id,organization_id,status,result,total_rows,imported_rows,rejected_rows").eq("id",batch_id).execute().data
    if not batch:
        raise HTTPException(404,"Carga no encontrada")
    require_org(user.id,batch[0]["organization_id"])
    return batch[0]

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

