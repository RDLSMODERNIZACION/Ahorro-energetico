from decimal import Decimal
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from .epen_optimization import (
    _simulate, _max_demand, _contracted, _period, _voltage_key,
    _tariff_key, _active_kwh, _rate_set, _d,
)

router = APIRouter(tags=["Optimización EPEN"])

COMPARABLE_TARIFF_CODES = {
    "CFI", "DEM", "DEP", "DFP",
    "EPI", "ERE", "EVA", "ECO",
    "CAV",
}


def _one_invoice_per_period(invoices):
    by_period = {}
    for invoice in invoices:
        period = _period(invoice)
        if not period:
            continue
        current = by_period.get(period)
        if current is None or _active_kwh(invoice) > _active_kwh(current):
            by_period[period] = invoice
    return [by_period[p] for p in sorted(by_period)]


def _actual_tariff_cost(invoice):
    total = Decimal("0")
    components = []

    for line in invoice.get("invoice_lines") or []:
        code = (line.get("concept_code") or "").upper().strip()
        if code not in COMPARABLE_TARIFF_CODES:
            continue

        amount = Decimal(str(line.get("net_amount") or 0))
        total += amount
        components.append({
            "code": code,
            "description": line.get("description"),
            "quantity": float(_d(line.get("quantity"))) if line.get("quantity") is not None else None,
            "unit_price": float(_d(line.get("unit_price"))) if line.get("unit_price") is not None else None,
            "net_amount": float(amount),
        })

    if not components:
        return None, []

    return total.quantize(Decimal("0.01")), components


def _proposed_t4_components(rates_rows, invoice, tariff, voltage, capacity_kw):
    period = _period(invoice)
    rates, schedule = _rate_set(rates_rows, period, tariff, voltage, capacity_kw)
    if not rates:
        return None, [], schedule

    active = _active_kwh(invoice)
    components = []
    total = Decimal("0")

    def add(code, quantity, unit_price, label):
        nonlocal total
        if unit_price is None:
            return
        amount = _d(quantity) * _d(unit_price)
        total += amount
        components.append({
            "code": code,
            "description": label,
            "quantity": float(_d(quantity)),
            "unit_price": float(_d(unit_price)),
            "net_amount": float(amount.quantize(Decimal("0.01"))),
        })

    if "CFI" in rates:
        total += rates["CFI"]
        components.append({
            "code": "CFI",
            "description": "Cargo fijo T4",
            "quantity": 1.0,
            "unit_price": float(rates["CFI"]),
            "net_amount": float(rates["CFI"]),
        })

    if "DEM" in rates:
        add("DEM", capacity_kw, rates["DEM"], "Demanda / capacidad T4")

    if "ECO" in rates:
        add("ECO", active, rates["ECO"], "Energía T4")

    if "CAV" in rates:
        add("CAV", active, rates["CAV"], "Cargo adicional variable")

    return total.quantize(Decimal("0.01")), components, schedule


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
        "invoice_lines(concept_code,description,quantity,unit_price,net_amount),"
        "meters(id,meter_number,service_name,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw)"
    ).eq("meter_id", meter_id).execute().data or []

    invoices = _one_invoice_per_period(invoices)
    if not invoices:
        return {"meter_id": meter_id, "mode": "none", "points": []}

    last12 = invoices[-12:]
    voltage = _voltage_key(invoices[-1].get("voltage_level") or meter.get("voltage_level"))
    current_tariff = _tariff_key(
        invoices[-1].get("current_tariff_code") or meter.get("current_tariff_code")
    )
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
            "current_cost_source": "actual_invoice_lines",
            "points": [],
        }

    points = []

    for invoice in invoices[-24:]:
        period = _period(invoice)
        tariff = _tariff_key(invoice.get("current_tariff_code") or current_tariff)
        inv_voltage = _voltage_key(invoice.get("voltage_level") or voltage)

        if tariff not in {"T3", "T3A"} or inv_voltage not in {"MT", "AT"}:
            continue

        peak_kw, off_kw = _contracted(invoice)
        demand = _max_demand(invoice)
        if peak_kw <= 0:
            peak_kw = demand

        unique_kw = max(peak_kw, off_kw, demand)
        target = "T4-MT" if inv_voltage == "MT" else "T4-AT"

        actual_cost, actual_components = _actual_tariff_cost(invoice)
        proposed_cost, proposed_components, proposed_schedule = _proposed_t4_components(
            rates, invoice, target, inv_voltage, unique_kw
        )

        available = actual_cost is not None and proposed_cost is not None

        if not available:
            points.append({
                "billing_period": period,
                "current_tariff": tariff,
                "recommended_tariff": target,
                "current_cost": None if actual_cost is None else float(actual_cost),
                "recommended_cost": None if proposed_cost is None else float(proposed_cost),
                "monthly_saving": 0.0,
                "annualized_saving": 0.0,
                "capacity_kw": float(unique_kw),
                "available": False,
                "reason": "missing_actual_tariff_lines" if actual_cost is None else "missing_tariff_schedule",
                "current_cost_source": "actual_invoice_lines",
                "current_components": actual_components,
                "proposed_components": proposed_components,
                "resolution_number": None if not proposed_schedule else proposed_schedule.get("resolution_number"),
                "billing_month": None if not proposed_schedule else proposed_schedule.get("billing_month"),
                "consumption_month": None if not proposed_schedule else proposed_schedule.get("consumption_month"),
            })
            continue

        saving = max(Decimal("0"), actual_cost - proposed_cost)

        points.append({
            "billing_period": period,
            "current_tariff": tariff,
            "recommended_tariff": target,
            "current_cost": float(actual_cost),
            "recommended_cost": float(proposed_cost),
            "monthly_saving": float(saving),
            "annualized_saving": float(saving * 12),
            "capacity_kw": float(unique_kw),
            "available": True,
            "reason": None,
            "current_cost_source": "actual_invoice_lines",
            "current_components": actual_components,
            "proposed_components": proposed_components,
            "resolution_number": (proposed_schedule or {}).get("resolution_number"),
            "billing_month": (proposed_schedule or {}).get("billing_month"),
            "consumption_month": (proposed_schedule or {}).get("consumption_month"),
        })

    return {
        "meter_id": meter_id,
        "mode": "t4",
        "current_tariff": current_tariff,
        "recommended_tariff": "T4-MT" if voltage == "MT" else "T4-AT",
        "months_over_100kw_last12": months_over_100,
        "taxes_included": False,
        "current_cost_source": "actual_invoice_lines",
        "formula": "actual_current_tariff_cost - simulated_proposed_tariff_cost",
        "points": points,
    }
