from datetime import datetime, timezone
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..auth import CurrentUser, current_user, require_org, require_org_admin, require_superadmin
from ..db import admin_db
from ..models import SiteCreate, MeterCreate, LocationUpdate

router = APIRouter(tags=["Catálogo"])

class MeterNameUpdate(BaseModel):
    service_name: str

class BillingStatusUpdate(BaseModel):
    status: Literal["active", "inactive", "removed"]
    note: str | None = None

class OrganizationCreate(BaseModel):
    name: str
    tax_id: str | None = None

class OrganizationUpdate(BaseModel):
    name: str | None = None
    tax_id: str | None = None

class MemberCreate(BaseModel):
    email: str
    role: Literal["admin", "analyst", "viewer"] = "viewer"

class MemberRoleUpdate(BaseModel):
    role: Literal["admin", "analyst", "viewer"]

def _auth_users():
    try:
        response = admin_db().auth.admin.list_users(page=1, per_page=1000)
        return list(getattr(response, "users", response) or [])
    except Exception:
        return []

def _user_email_map() -> dict[str, str]:
    return {str(user.id): str(user.email or "") for user in _auth_users()}

@router.get("/organizations")
def organizations(user: CurrentUser = Depends(current_user)):
    memberships = admin_db().table("organization_members").select("organization_id,role,organizations(*)").eq("user_id",user.id).execute()
    rows = memberships.data or []
    for row in rows:
        row["is_superadmin"] = user.is_superadmin
    return rows

@router.get("/admin/me")
def admin_me(user: CurrentUser = Depends(current_user)):
    return {"is_superadmin": user.is_superadmin, "email": user.email}

@router.get("/admin/organizations")
def admin_organizations(user: CurrentUser = Depends(current_user)):
    require_superadmin(user)
    db = admin_db()
    rows = db.table("organizations").select("*").order("name").execute().data or []
    members = db.table("organization_members").select("organization_id").execute().data or []
    counts: dict[str, int] = {}
    for member in members:
        key = str(member.get("organization_id"))
        counts[key] = counts.get(key, 0) + 1
    for row in rows:
        row["member_count"] = counts.get(str(row.get("id")), 0)
    return rows

@router.post("/admin/organizations", status_code=201)
def create_organization(body: OrganizationCreate, user: CurrentUser = Depends(current_user)):
    require_superadmin(user)
    name = body.name.strip()
    if len(name) < 2:
        raise HTTPException(422, "El nombre debe tener al menos 2 caracteres")
    db = admin_db()
    row = db.table("organizations").insert({"name": name, "tax_id": body.tax_id or None}).execute().data[0]
    db.table("organization_members").insert({"organization_id": row["id"], "user_id": user.id, "role": "admin"}).execute()
    row["member_count"] = 1
    return row

@router.patch("/admin/organizations/{organization_id}")
def update_organization(organization_id: str, body: OrganizationUpdate, user: CurrentUser = Depends(current_user)):
    require_superadmin(user)
    payload = {}
    if body.name is not None:
        name = body.name.strip()
        if len(name) < 2:
            raise HTTPException(422, "El nombre debe tener al menos 2 caracteres")
        payload["name"] = name
    if body.tax_id is not None:
        payload["tax_id"] = body.tax_id.strip() or None
    if not payload:
        raise HTTPException(422, "No hay cambios para guardar")
    rows = admin_db().table("organizations").update(payload).eq("id", organization_id).execute().data
    if not rows:
        raise HTTPException(404, "Organización inexistente")
    return rows[0]

@router.get("/admin/organizations/{organization_id}/members")
def list_organization_members(organization_id: str, user: CurrentUser = Depends(current_user)):
    if not user.is_superadmin:
        require_org_admin(user.id, organization_id)
    rows = admin_db().table("organization_members").select("id,user_id,role,created_at").eq("organization_id", organization_id).order("created_at").execute().data or []
    emails = _user_email_map()
    for row in rows:
        row["email"] = emails.get(str(row.get("user_id")), "")
    return rows

@router.post("/admin/organizations/{organization_id}/members", status_code=201)
def add_organization_member(organization_id: str, body: MemberCreate, user: CurrentUser = Depends(current_user)):
    if not user.is_superadmin:
        require_org_admin(user.id, organization_id)
    email = body.email.strip().lower()
    if "@" not in email:
        raise HTTPException(422, "Correo inválido")
    target = next((candidate for candidate in _auth_users() if str(candidate.email or "").lower() == email), None)
    if target is None:
        raise HTTPException(404, "El usuario todavía no existe en la plataforma")
    db = admin_db()
    user_id = str(target.id)
    existing = db.table("organization_members").select("id").eq("organization_id", organization_id).eq("user_id", user_id).limit(1).execute().data
    if existing:
        row = db.table("organization_members").update({"role": body.role}).eq("id", existing[0]["id"]).execute().data[0]
    else:
        row = db.table("organization_members").insert({"organization_id": organization_id, "user_id": user_id, "role": body.role}).execute().data[0]
    row["email"] = str(target.email or email)
    return row

@router.patch("/admin/organizations/{organization_id}/members/{member_id}")
def update_organization_member(organization_id: str, member_id: str, body: MemberRoleUpdate, user: CurrentUser = Depends(current_user)):
    if not user.is_superadmin:
        require_org_admin(user.id, organization_id)
    rows = admin_db().table("organization_members").update({"role": body.role}).eq("id", member_id).eq("organization_id", organization_id).execute().data
    if not rows:
        raise HTTPException(404, "Miembro inexistente")
    return rows[0]

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
    ap_rows = db.table("public_lighting_meters").select("linked_meter_id").eq("organization_id", organization_id).execute().data
    ap_meter_ids = {str(row["linked_meter_id"]) for row in ap_rows if row.get("linked_meter_id")}
    rows = db.table("meters").select("*,sites(name,address)").eq("organization_id", organization_id).order("meter_number").execute().data
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
    payload = {"status": body.status, "expected_monthly": body.status != "removed", "removed_at": now.date().isoformat() if body.status == "removed" else None, "notes": body.note or labels[body.status], "updated_at": now.isoformat()}
    updated = db.table("meters").update(payload).eq("id",meter_id).execute().data[0]
    if body.status == "removed":
        db.table("missing_invoice_alerts").update({"status":"resolved", "resolved_at":now.isoformat(), "resolution_note":labels[body.status]}).eq("meter_id",meter_id).eq("status","open").execute()
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
    rows = db.table("meter_locations").select("meter_id,latitude,longitude,valid_from,source").in_("meter_id", meter_ids).is_("valid_to", "null").order("valid_from", desc=True).execute().data
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
    rows = db.table("meter_locations").select("*").eq("meter_id",meter_id).is_("valid_to","null").order("valid_from", desc=True).limit(1).execute().data
    if not rows:
        return None
    return rows[0]

@router.put("/meters/{meter_id}/location")
def update_location(meter_id: str, body: LocationUpdate, user: CurrentUser = Depends(current_user)):
    meter = admin_db().table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not meter:
        raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,meter[0]["organization_id"],write=True)
    admin_db().table("meter_locations").update({"valid_to":datetime.now(timezone.utc).isoformat()}).eq("meter_id",meter_id).is_("valid_to","null").execute()
    row={"meter_id":meter_id,"latitude":str(body.latitude),"longitude":str(body.longitude),"source":"manual_map","created_by":user.id}
    return admin_db().table("meter_locations").insert(row).execute().data[0]
