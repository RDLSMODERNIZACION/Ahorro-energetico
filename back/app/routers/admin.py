from typing import Literal
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..auth import CurrentUser, current_user, require_org_admin, require_superadmin
from ..db import admin_db

router = APIRouter(tags=["Administración"])
Role = Literal["admin", "analyst", "viewer"]

class OrganizationCreate(BaseModel):
    name: str
    tax_id: str | None = None

class MemberCreate(BaseModel):
    user_id: str
    role: Role = "viewer"

class MemberRoleUpdate(BaseModel):
    role: Role

@router.get("/admin/me")
def admin_me(user: CurrentUser = Depends(current_user)):
    return {"is_superadmin": user.is_superadmin, "email": user.email}

@router.get("/admin/organizations")
def admin_organizations(user: CurrentUser = Depends(current_user)):
    require_superadmin(user)
    db = admin_db()
    organizations = db.table("organizations").select("*").order("name").execute().data or []
    memberships = db.table("organization_members").select("organization_id").execute().data or []
    counts = {}
    for membership in memberships:
        org_id = str(membership.get("organization_id"))
        counts[org_id] = counts.get(org_id, 0) + 1
    for organization in organizations:
        organization["member_count"] = counts.get(str(organization.get("id")), 0)
    return organizations

@router.post("/admin/organizations", status_code=201)
def create_organization(body: OrganizationCreate, user: CurrentUser = Depends(current_user)):
    require_superadmin(user)
    name = body.name.strip()
    if len(name) < 2:
        raise HTTPException(422, "El nombre debe tener al menos 2 caracteres")
    db = admin_db()
    organization = db.table("organizations").insert({"name": name, "tax_id": body.tax_id or None}).execute().data[0]
    db.table("organization_members").insert({"organization_id": organization["id"], "user_id": user.id, "role": "admin"}).execute()
    organization["member_count"] = 1
    return organization

@router.get("/admin/organizations/{organization_id}/members")
def list_members(organization_id: str, user: CurrentUser = Depends(current_user)):
    if not user.is_superadmin:
        require_org_admin(user.id, organization_id)
    return admin_db().table("organization_members").select("id,user_id,role,created_at").eq("organization_id", organization_id).order("created_at").execute().data or []

@router.post("/admin/organizations/{organization_id}/members", status_code=201)
def add_member(organization_id: str, body: MemberCreate, user: CurrentUser = Depends(current_user)):
    if not user.is_superadmin:
        require_org_admin(user.id, organization_id)
    db = admin_db()
    existing = db.table("organization_members").select("id").eq("organization_id", organization_id).eq("user_id", body.user_id).limit(1).execute().data
    if existing:
        return db.table("organization_members").update({"role": body.role}).eq("id", existing[0]["id"]).execute().data[0]
    return db.table("organization_members").insert({"organization_id": organization_id, "user_id": body.user_id, "role": body.role}).execute().data[0]

@router.patch("/admin/organizations/{organization_id}/members/{member_id}")
def update_member_role(organization_id: str, member_id: str, body: MemberRoleUpdate, user: CurrentUser = Depends(current_user)):
    if not user.is_superadmin:
        require_org_admin(user.id, organization_id)
    rows = admin_db().table("organization_members").update({"role": body.role}).eq("id", member_id).eq("organization_id", organization_id).execute().data
    if not rows:
        raise HTTPException(404, "Miembro inexistente")
    return rows[0]
