from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from ..models import SiteCreate, MeterCreate, LocationUpdate

router = APIRouter(tags=["Catálogo"])

@router.get("/organizations")
def organizations(user: CurrentUser = Depends(current_user)):
    memberships = admin_db().table("organization_members").select("organization_id,role,organizations(*)").eq("user_id",user.id).execute()
    return memberships.data

@router.get("/organizations/{organization_id}/sites")
def list_sites(organization_id: str, user: CurrentUser = Depends(current_user)):
    require_org(user.id, organization_id)
    return admin_db().table("sites").select("*").eq("organization_id",organization_id).order("name").execute().data

@router.post("/sites", status_code=201)
def create_site(body: SiteCreate, user: CurrentUser = Depends(current_user)):
    require_org(user.id, body.organization_id, write=True)
    return admin_db().table("sites").insert(body.model_dump(mode="json", exclude_none=True)).execute().data[0]

@router.get("/organizations/{organization_id}/meters")
def list_meters(organization_id: str, user: CurrentUser = Depends(current_user)):
    require_org(user.id, organization_id)
    return admin_db().table("meters").select("*,sites(name,address)").eq("organization_id",organization_id).order("meter_number").execute().data

@router.post("/meters", status_code=201)
def create_meter(body: MeterCreate, user: CurrentUser = Depends(current_user)):
    require_org(user.id, body.organization_id, write=True)
    return admin_db().table("meters").insert(body.model_dump(mode="json", exclude_none=True)).execute().data[0]

@router.put("/meters/{meter_id}/location")
def update_location(meter_id: str, body: LocationUpdate, user: CurrentUser = Depends(current_user)):
    meter = admin_db().table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not meter: raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,meter[0]["organization_id"],write=True)
    admin_db().table("meter_locations").update({"valid_to":datetime.now(timezone.utc).isoformat()}).eq("meter_id",meter_id).is_("valid_to","null").execute()
    row={"meter_id":meter_id,"latitude":str(body.latitude),"longitude":str(body.longitude),"created_by":user.id}
    return admin_db().table("meter_locations").insert(row).execute().data[0]
