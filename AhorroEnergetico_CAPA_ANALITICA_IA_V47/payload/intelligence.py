from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..energy_intelligence import load_energy_knowledge, refresh_energy_intelligence

router = APIRouter(tags=["Inteligencia energética"])


@router.post("/organizations/{organization_id}/energy-intelligence/refresh")
def refresh_energy_layer(
    organization_id: str,
    user: CurrentUser = Depends(current_user),
):
    require_org(user.id, organization_id, write=True)
    return refresh_energy_intelligence(organization_id)


@router.get("/organizations/{organization_id}/energy-intelligence")
def get_energy_layer(
    organization_id: str,
    user: CurrentUser = Depends(current_user),
):
    require_org(user.id, organization_id)
    return load_energy_knowledge(organization_id)
