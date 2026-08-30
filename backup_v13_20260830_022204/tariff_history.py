from decimal import Decimal
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from .epen_optimization import (
    _simulate, _max_demand, _contracted, _period, _voltage_key,
    _tariff_key, _active_kwh,
)

router = APIRouter(tags=["Optimización EPEN"])

# Conceptos que representan el costo tarifario comparable.
# Se excluyen impuestos, deuda, fondos/cargos extraordinarios y otros conceptos
# que no desaparecen por cambiar de T3/T3A a T4.
COMPARABLE_TARIFF_CODES = {
    "CFI", "DEM", "DEP", "DFP",
    "EPI", "ERE", "EVA", "ECO",
    "CAV",
}


def _one_invoice_per_period(invoices):
    """Conserva la factura energética principal de cada período."""
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
    """
    Costo REAL facturado de la tarifa vigente.

    No reconstruye T3/T3A con tariff_rates.
    Suma directamente net_amount de los conceptos tarifarios comparables
    presentes en invoice_lines.
    """
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
            "quantity": line.get("quantity"),
            "unit_price": line.get("unit_price"),
            "net_amount": float(amount),
        })

    if not components:
        return None, []

    return total.quantize(Decimal("0.01")), components


@router.get("/meters/{meter_id}/tariff-saving-history")
def tariff_saving_history(meter_id: str, user: CurrentUser = Depends(current_user)):
    """
    Histórico mensual T3/T3A REAL facturada vs T4 simulada.

    Fórmula:
        ahorro = subtotal tarifario real T3/T3A - subtotal T4 simulado

    El lado actual usa invoice_lines reales.
    Sólo se simula la tarifa propuesta T4.
    """
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

        # ACTUAL: factura real, no simulada.
        actual_cost, actual_components = _actual_tariff_cost(invoice)

        # PROPUESTA: sólo T4 se simula.
        proposed_cost, proposed_schedule = _simulate(
            rates, invoice, target, inv_voltage, unique_kw, Decimal("0")
        )

        available = actual_cost is not None and proposed_cost is not None

        if not available:
            reason = (
                "missing_actual_tariff_lines" if actual_cost is None
                else "missing_tariff_schedule"
            )
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
                "reason": reason,
                "current_cost_source": "actual_invoice_lines",
                "current_components": actual_components,
                "resolution_number": None,
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
            "resolution_number": (proposed_schedule or {}).get("resolution_number"),
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
