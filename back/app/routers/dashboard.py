from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from .invoices import INVOICE_LIST_SELECT, _compact_invoice, _resolve_rows

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
        .select(
            "id,organization_id,tracking_code,meter_number,nis,supply_number,"
            "contract_number,service_code,service_name,cadastral_number,customer_number,"
            "customer_type,contract_type,current_tariff_code,voltage_level,"
            "contracted_kw_peak,contracted_kw_off_peak,status,expected_monthly,"
            "first_seen_period,last_seen_period,notes,sites(name,address)"
        )
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
    query = (
        admin_db()
        .table("invoices")
        .select(INVOICE_LIST_SELECT)
        .eq("organization_id", organization_id)
    )
    # billing_period is the canonical month in the app. Fall back to period_start
    # is handled by the regular invoice endpoint for older records.
    rows = (
        query.gte("billing_period", period + "-01")
        .lt("billing_period", period + "-32")
        .order("period_start", desc=True)
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
