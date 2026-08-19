from fastapi import APIRouter,Depends,HTTPException
from ..auth import CurrentUser,current_user,require_tariff_editor
from ..db import admin_db
from ..models import TariffScheduleCreate,TariffRateCreate

router=APIRouter(prefix="/tariffs",tags=["Tarifas"])

@router.get("/categories")
def categories(user:CurrentUser=Depends(current_user)):
    return admin_db().table("tariff_categories").select("*").order("code").execute().data

@router.get("/schedules")
def schedules(user:CurrentUser=Depends(current_user)):
    return admin_db().table("tariff_schedules").select("*").order("consumption_month",desc=True).execute().data

@router.post("/schedules",status_code=201)
def create_schedule(body:TariffScheduleCreate,user:CurrentUser=Depends(current_user)):
    require_tariff_editor(user.id)
    return admin_db().table("tariff_schedules").insert(body.model_dump(mode="json",exclude_none=True)).execute().data[0]

@router.get("/schedules/{schedule_id}/rates")
def rates(schedule_id:str,user:CurrentUser=Depends(current_user)):
    return admin_db().table("tariff_rates").select("*,tariff_categories(code,name)").eq("schedule_id",schedule_id).execute().data

@router.post("/schedules/{schedule_id}/rates",status_code=201)
def create_rate(schedule_id:str,body:TariffRateCreate,user:CurrentUser=Depends(current_user)):
    require_tariff_editor(user.id)
    cat=admin_db().table("tariff_categories").select("id").eq("code",body.category_code).limit(1).execute().data
    if not cat: raise HTTPException(404,"Categoría tarifaria inexistente")
    data=body.model_dump(mode="json",exclude_none=True);data.pop("category_code");data.update({"schedule_id":schedule_id,"category_id":cat[0]["id"]})
    return admin_db().table("tariff_rates").insert(data).execute().data[0]
