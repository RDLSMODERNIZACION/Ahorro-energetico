from concurrent.futures import ThreadPoolExecutor
from math import sqrt
from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db


router = APIRouter(tags=["Facturas"])


INVOICE_LIST_SELECT = (
    "id,organization_id,meter_id,invoice_number,"
    "period_start,period_end,issue_date,due_date,current_tariff_code,"
    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,subtotal,"
    "net_taxable,total_amount,"
    "amount_due,billing_period,tariff_name,tariff_class,vat_amount,"
    "previous_debt_amount,"
    "meters(id,meter_number,nis,tracking_code,supply_number,contract_number,"
    "service_code,service_name,cadastral_number,current_tariff_code,"
    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,sites(name,address)),"
    "invoice_measurements(active_energy_kwh,reactive_energy_kvarh,demand_kw,"
    "power_factor,registered_demand_peak_kw,registered_demand_off_peak_kw,"
    "tangent_phi,reactive_surcharge_percent,meter_number,measurement_type),"
    "invoice_lines(concept_code,description,quantity,unit_price,net_amount)"
)

SUMMARY_LINE_CODES = {"DEM", "DEP", "EXC", "COS"}


def _num(value):
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _resolve_power_factor(invoice: dict) -> dict:
    measurements = invoice.get("invoice_measurements") or []
    lines = invoice.get("invoice_lines") or []

    cos_charge = sum(
        max(0.0, _num(line.get("net_amount")))
        for line in lines
        if str(line.get("concept_code") or "").upper().strip() == "COS"
    )
    line_penalized = cos_charge > 0

    resolved_values = []
    any_penalty = line_penalized

    for measurement in measurements:
        reported = _num(measurement.get("power_factor"))
        tangent = _num(measurement.get("tangent_phi"))
        surcharge = _num(measurement.get("reactive_surcharge_percent"))

        resolved = None
        source = None

        if reported > 0:
            resolved = reported
            source = "reported"
        elif tangent > 0:
            resolved = 1.0 / sqrt(1.0 + tangent * tangent)
            source = "tangent_phi"

        penalized = surcharge > 0 or line_penalized
        any_penalty = any_penalty or penalized

        measurement["resolved_power_factor"] = (
            round(resolved, 6) if resolved is not None else None
        )
        measurement["power_factor_source"] = source
        measurement["power_factor_penalized"] = penalized

        if resolved is not None and resolved > 0:
            resolved_values.append(resolved)

    invoice["resolved_power_factor"] = (
        round(min(resolved_values), 6) if resolved_values else None
    )
    invoice["power_factor_penalized"] = any_penalty
    invoice["power_factor_value_available"] = bool(resolved_values)
    invoice["power_factor_charge_amount"] = round(cos_charge, 2)

    return invoice


def _resolve_rows(rows):
    return [_resolve_power_factor(row) for row in rows]


def _compact_invoice(invoice: dict) -> dict:
    """Reduce dashboard payload while preserving the fields used by metrics()."""
    measurements = invoice.get("invoice_measurements") or []
    if measurements:
        resolved = [
            _num(row.get("resolved_power_factor"))
            for row in measurements
            if _num(row.get("resolved_power_factor")) > 0
        ]
        reported = [
            _num(row.get("power_factor"))
            for row in measurements
            if _num(row.get("power_factor")) > 0
        ]
        compact_measurement = {
            "active_energy_kwh": sum(_num(row.get("active_energy_kwh")) for row in measurements),
            "reactive_energy_kvarh": sum(_num(row.get("reactive_energy_kvarh")) for row in measurements),
            "demand_kw": max([_num(row.get("demand_kw")) for row in measurements] + [0.0]),
            "registered_demand_peak_kw": max([_num(row.get("registered_demand_peak_kw")) for row in measurements] + [0.0]),
            "registered_demand_off_peak_kw": max([_num(row.get("registered_demand_off_peak_kw")) for row in measurements] + [0.0]),
            "power_factor": min(reported) if reported else None,
            "resolved_power_factor": min(resolved) if resolved else invoice.get("resolved_power_factor"),
            "tangent_phi": max([_num(row.get("tangent_phi")) for row in measurements] + [0.0]),
            "reactive_surcharge_percent": max([_num(row.get("reactive_surcharge_percent")) for row in measurements] + [0.0]),
            "power_factor_penalized": bool(invoice.get("power_factor_penalized")),
            "measurement_type": "summary",
        }
        invoice["invoice_measurements"] = [compact_measurement]
    else:
        invoice["invoice_measurements"] = []

    invoice["invoice_lines"] = [
        line
        for line in (invoice.get("invoice_lines") or [])
        if str(line.get("concept_code") or "").upper().strip() in SUMMARY_LINE_CODES
    ]
    return invoice


def _fetch_invoice_page(
    organization_id: str,
    meter_id: str | None,
    start: int,
    end: int,
):
    query = (
        admin_db()
        .table("invoices")
        .select(INVOICE_LIST_SELECT)
        .eq("organization_id", organization_id)
    )
    if meter_id:
        query = query.eq("meter_id", meter_id)
    return (
        query.order("period_start", desc=True)
        .order("id", desc=True)
        .range(start, end)
        .execute()
        .data
    )


@router.get("/organizations/{organization_id}/invoices")
def invoices(
    organization_id: str,
    meter_id: str | None = None,
    limit: int = Query(100, ge=1, le=5000),
    summary: bool = Query(False),
    user: CurrentUser = Depends(current_user),
):
    require_org(user.id, organization_id)

    page_size = 1000
    page_specs = [
        (offset, min(offset + page_size - 1, limit - 1))
        for offset in range(0, limit, page_size)
    ]

    workers = min(5, len(page_specs))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [
            pool.submit(
                _fetch_invoice_page,
                organization_id,
                meter_id,
                start,
                end,
            )
            for start, end in page_specs
        ]
        pages = [future.result() for future in futures]

    rows = []
    for (start, end), page in zip(page_specs, pages):
        rows.extend(page)
        expected_size = end - start + 1
        if len(page) < expected_size:
            break

    resolved = _resolve_rows(rows[:limit])
    if summary:
        return [_compact_invoice(row) for row in resolved]
    return resolved


@router.get("/invoices/{invoice_id}")
def invoice(invoice_id: str, user: CurrentUser = Depends(current_user)):
    data = (
        admin_db()
        .table("invoices")
        .select("*,meters(*,sites(*)),invoice_measurements(*),invoice_lines(*)")
        .eq("id", invoice_id)
        .limit(1)
        .execute()
        .data
    )
    if not data:
        raise HTTPException(404, "Factura inexistente")
    require_org(user.id, data[0]["organization_id"])
    return _resolve_power_factor(data[0])


@router.delete("/invoices/{invoice_id}", status_code=204)
def delete_invoice(invoice_id: str, user: CurrentUser = Depends(current_user)):
    data = (
        admin_db()
        .table("invoices")
        .select("organization_id")
        .eq("id", invoice_id)
        .limit(1)
        .execute()
        .data
    )
    if not data:
        raise HTTPException(404, "Factura inexistente")
    require_org(user.id, data[0]["organization_id"], write=True)
    admin_db().table("invoices").delete().eq("id", invoice_id).execute()
