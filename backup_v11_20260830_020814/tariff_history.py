from decimal import Decimal
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from .epen_optimization import _simulate, _max_demand, _contracted, _period, _voltage_key, _tariff_key

router = APIRouter(tags=["Optimización EPEN"])


@router.get("/meters/{meter_id}/tariff-saving-history")
def tariff_saving_history(meter_id: str, user: CurrentUser = Depends(current_user)):
    db = admin_db()

    meter_rows = db.table("meters").select(
        "id,organization_id,meter_number,service_name,current_tariff_code,voltage_level"
    ).eq("id", meter_id).limit(1).execute().data or []

    if not meter_rows:
        return {"meter_id": meter_id, "mode": "none", "points": []}

    meter = meter_rows[0]
    require_org(user.id, meter["organization_id"])

    rates = db.table("tariff_rates").select(
        "unit_price,voltage_level,min_capacity_kw,max_capacity_kw,"
        "charge_code,time_band,tariff_categories(code),"
        "tariff_schedules(resolution_number,consumption_month,billing_month,valid_from,valid_to)"
    ).execute().data or []

    invoices = db.table("invoices").select(
        "id,meter_id,billing_period,period_start,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw,"
        "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,"
        "registered_demand_off_peak_kw,time_band),"
        "invoice_lines(concept_code,quantity,unit_price,net_amount),"
        "meters(id,meter_number,service_name,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw)"
    ).eq("meter_id", meter_id).execute().data or []

    invoices.sort(key=lambda x: _period(x))
    if not invoices:
        return {"meter_id": meter_id, "mode": "none", "points": []}

    last12 = invoices[-12:]
    voltage = _voltage_key(invoices[-1].get("voltage_level") or meter.get("voltage_level"))
    current_tariff = _tariff_key(invoices[-1].get("current_tariff_code") or meter.get("current_tariff_code"))
    months_over_100 = sum(1 for x in last12 if _max_demand(x) >= Decimal("100"))

    candidate = (
        voltage in {"MT", "AT"}
        and current_tariff in {"T3", "T3A"}
        and len(last12) >= 12
        and months_over_100 == 12
    )

    if not candidate:
        return {
            "meter_id": meter_id,
            "mode": "none",
            "current_tariff": current_tariff,
            "recommended_tariff": None,
            "months_over_100kw_last12": months_over_100,
            "taxes_included": False,
            "points": [],
        }

    points = []
    for invoice in invoices[-24:]:
        tariff = _tariff_key(invoice.get("current_tariff_code") or current_tariff)
        inv_voltage = _voltage_key(invoice.get("voltage_level") or voltage)

        if tariff not in {"T3", "T3A"} or inv_voltage not in {"MT", "AT"}:
            continue

        peak_kw, off_kw = _contracted(invoice)
        demand = _max_demand(invoice)

        if peak_kw <= 0:
            peak_kw = demand
        if off_kw <= 0:
            off_kw = peak_kw

        unique_kw = max(peak_kw, off_kw, demand)
        target = "T4-MT" if inv_voltage == "MT" else "T4-AT"

        current_cost, current_schedule = _simulate(
            rates, invoice, tariff, inv_voltage, peak_kw, off_kw
        )
        proposed_cost, proposed_schedule = _simulate(
            rates, invoice, target, inv_voltage, unique_kw, Decimal("0")
        )

        if current_cost is None or proposed_cost is None:
            continue

        saving = max(Decimal("0"), current_cost - proposed_cost)
        points.append({
            "billing_period": _period(invoice),
            "current_tariff": tariff,
            "recommended_tariff": target,
            "current_cost": float(current_cost),
            "recommended_cost": float(proposed_cost),
            "monthly_saving": float(saving),
            "annualized_saving": float(saving * 12),
            "capacity_kw": float(unique_kw),
            "resolution_number": (
                (proposed_schedule or current_schedule or {}).get("resolution_number")
            ),
        })

    return {
        "meter_id": meter_id,
        "mode": "t4",
        "current_tariff": current_tariff,
        "recommended_tariff": "T4-MT" if voltage == "MT" else "T4-AT",
        "months_over_100kw_last12": months_over_100,
        "taxes_included": False,
        "points": points,
    }
