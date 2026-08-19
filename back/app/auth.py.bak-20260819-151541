from dataclasses import dataclass
from fastapi import Header, HTTPException
from .db import admin_db

@dataclass(frozen=True)
class CurrentUser:
    id: str
    email: str | None

def current_user(authorization: str | None = Header(default=None)) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Falta el token de acceso")
    token = authorization.split(" ", 1)[1].strip()
    try:
        response = admin_db().auth.get_user(token)
        user = response.user
        if not user:
            raise ValueError("Usuario inexistente")
        return CurrentUser(id=str(user.id), email=user.email)
    except Exception as exc:
        raise HTTPException(401, "Token inválido o vencido") from exc

def require_org(user_id: str, organization_id: str, write: bool = False) -> dict:
    query = (admin_db().table("organization_members").select("role")
             .eq("organization_id", organization_id).eq("user_id", user_id).limit(1).execute())
    if not query.data:
        raise HTTPException(403, "El usuario no pertenece a la organización")
    membership = query.data[0]
    if write and membership["role"] not in ("admin", "analyst"):
        raise HTTPException(403, "El usuario no tiene permiso para modificar datos")
    return membership

def require_tariff_editor(user_id: str) -> None:
    result = (admin_db().table("organization_members").select("role")
              .eq("user_id", user_id).in_("role", ["admin", "analyst"]).limit(1).execute())
    if not result.data:
        raise HTTPException(403, "El usuario no puede modificar cuadros tarifarios")
