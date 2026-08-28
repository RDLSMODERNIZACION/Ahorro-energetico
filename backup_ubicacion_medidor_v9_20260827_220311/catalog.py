from datetime import datetime, timezone
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from ..models import SiteCreate, MeterCreate, LocationUpdate

router = APIRouter(tags=["Catálogo"])

class BillingStatusUpdate(BaseModel):
    status: Literal["active", "inactive", "removed"]
    note: str | None = None

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

@router.put("/meters/{meter_id}/billing-status")
def update_billing_status(meter_id: str, body: BillingStatusUpdate, user: CurrentUser = Depends(current_user)):
    db = admin_db()
    rows = db.table("meters").select("organization_id,meter_number").eq("id",meter_id).limit(1).execute().data
    if not rows:
        raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,rows[0]["organization_id"],write=True)
    now = datetime.now(timezone.utc)
    labels = {"active":"Continúa activo", "inactive":"Sin facturación reciente - posible baja", "removed":"Baja confirmada"}
    payload = {
        "status": body.status,
        # Una posible baja sigue debiendo factura hasta confirmar la baja.
        "expected_monthly": body.status != "removed",
        "removed_at": now.date().isoformat() if body.status == "removed" else None,
        "notes": body.note or labels[body.status],
        "updated_at": now.isoformat(),
    }
    updated = db.table("meters").update(payload).eq("id",meter_id).execute().data[0]
    if body.status == "removed":
        db.table("missing_invoice_alerts").update({
            "status":"resolved", "resolved_at":now.isoformat(),
            "resolution_note":labels[body.status]
        }).eq("meter_id",meter_id).eq("status","open").execute()
    return updated

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
