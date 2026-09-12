from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from .invoices import INVOICE_LIST_SELECT, _compact_invoice, _next_month, _resolve_rows

router = APIRouter(tags=["Dashboard"])


def _meter_rows(organization_id: str):
    db = admin_db()
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


def _latest_period(organization_id: str):
    rows = (
        admin_db()
        .table("invoices")
        .select("billing_period,period_start")
        .eq("organization_id", organization_id)
        .order("billing_period", desc=True)
        .order("period_start", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not rows:
        return None
    row = rows[0]
    return str(row.get("billing_period") or row.get("period_start") or "")[:7] or None


def _latest_invoices(organization_id: str, period: str | None):
    if not period:
        return []
    rows = (
        admin_db()
        .table("invoices")
        .select(INVOICE_LIST_SELECT)
        .eq("organization_id", organization_id)
        .gte("billing_period", period + "-01")
        .lt("billing_period", _next_month(period))
        .order("period_start", desc=True)
        .order("id", desc=True)
        .limit(500)
        .execute()
        .data
    )
    resolved = _resolve_rows(rows)
    return [_compact_invoice(row) for row in resolved]


@router.get("/organizations/{organization_id}/dashboard-bootstrap")
def dashboard_bootstrap(
    organization_id: str,
    user: CurrentUser = Depends(current_user),
):
    require_org(user.id, organization_id)

    period = _latest_period(organization_id)
    with ThreadPoolExecutor(max_workers=2) as pool:
        meters_future = pool.submit(_meter_rows, organization_id)
        invoices_future = pool.submit(_latest_invoices, organization_id, period)
        meters = meters_future.result()
        invoices = invoices_future.result()

    return {
        "period": period,
        "meters": meters,
        "invoices": invoices,
    }
