from datetime import datetime, timezone
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from ..models import SiteCreate, MeterCreate, LocationUpdate

router = APIRouter(tags=["Catálogo"])

class MeterNameUpdate(BaseModel):
    service_name: str

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
    db = admin_db()

    # Alumbrado Público tiene su módulo y seguimiento propios. Los medidores
    # generales vinculados a public_lighting_meters no deben volver a contarse
    # como Dependencias (esperadas, recibidas, faltantes o posibles bajas).
    ap_rows = (
        db.table("public_lighting_meters")
        .select("linked_meter_id")
        .eq("organization_id", organization_id)
        .execute()
        .data
    )
    ap_meter_ids = {
        str(row["linked_meter_id"])
        for row in ap_rows
        if row.get("linked_meter_id")
    }

    rows = (
        db.table("meters")
        .select("*,sites(name,address)")
        .eq("organization_id", organization_id)
        .order("meter_number")
        .execute()
        .data
    )
    return [row for row in rows if str(row.get("id")) not in ap_meter_ids]

@router.put("/meters/{meter_id}/name")
def update_meter_name(meter_id: str, body: MeterNameUpdate, user: CurrentUser = Depends(current_user)):
    db = admin_db()
    rows = db.table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not rows:
        raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,rows[0]["organization_id"],write=True)
    name = body.service_name.strip()
    if len(name) < 2:
        raise HTTPException(422,"El nombre debe tener al menos 2 caracteres")
    updated = db.table("meters").update({"service_name":name,"updated_at":datetime.now(timezone.utc).isoformat()}).eq("id",meter_id).execute().data
    return updated[0]
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



@router.get("/organizations/{organization_id}/meter-locations")
def list_meter_locations(organization_id: str, user: CurrentUser = Depends(current_user)):
    require_org(user.id, organization_id)
    db = admin_db()
    meters = db.table("meters").select("id").eq("organization_id", organization_id).execute().data
    meter_ids = [row["id"] for row in meters]
    if not meter_ids:
        return []
    rows = (
        db.table("meter_locations")
        .select("meter_id,latitude,longitude,valid_from,source")
        .in_("meter_id", meter_ids)
        .is_("valid_to", "null")
        .order("valid_from", desc=True)
        .execute()
        .data
    )
    latest = {}
    for row in rows:
        latest.setdefault(row["meter_id"], row)
    return list(latest.values())
@router.get("/meters/{meter_id}/location")
def get_location(meter_id: str, user: CurrentUser = Depends(current_user)):
    db = admin_db()
    meter = db.table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not meter:
        raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,meter[0]["organization_id"])
    rows = (
        db.table("meter_locations")
        .select("*")
        .eq("meter_id",meter_id)
        .is_("valid_to","null")
        .order("valid_from", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not rows:
        return None
    return rows[0]
@router.put("/meters/{meter_id}/location")
def update_location(meter_id: str, body: LocationUpdate, user: CurrentUser = Depends(current_user)):
    meter = admin_db().table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not meter: raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,meter[0]["organization_id"],write=True)
    admin_db().table("meter_locations").update({"valid_to":datetime.now(timezone.utc).isoformat()}).eq("meter_id",meter_id).is_("valid_to","null").execute()
    row={"meter_id":meter_id,"latitude":str(body.latitude),"longitude":str(body.longitude),"source":"manual_map","created_by":user.id}
    return admin_db().table("meter_locations").insert(row).execute().data[0]



