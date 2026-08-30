from decimal import Decimal
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db
from .epen_optimization import (
    _max_demand, _contracted, _period, _voltage_key,
    _tariff_key, _active_kwh, _rate_set, _d,
)

router = APIRouter(tags=["Optimización EPEN"])

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
    """Subtotal REAL comparable de la factura actual."""
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


def _target_same_tariff_components(rates_rows, invoice, tariff, target_voltage, capacity_kw):
    """
    Simula la MISMA categoría tarifaria en otro nivel de tensión.

    Para BT→MT no inventamos consumos horarios:
    reutilizamos las cantidades REALES de invoice_lines (DEP, EPI, ERE, EVA, etc.)
    y las valorizamos con los precios oficiales MT del mismo período.
    """
    period = _period(invoice)
    rates, schedule = _rate_set(rates_rows, period, tariff, target_voltage, capacity_kw)
    if not rates:
        return None, [], schedule

    actual_lines = invoice.get("invoice_lines") or []
    components = []
    total = Decimal("0")
    used_codes = set()

    for line in actual_lines:
        code = (line.get("concept_code") or "").upper().strip()
        if code not in COMPARABLE_TARIFF_CODES or code not in rates:
            continue

        used_codes.add(code)
        rate = _d(rates[code])

        if code == "CFI":
            quantity = Decimal("1")
        else:
            quantity = _d(line.get("quantity"))
            if quantity <= 0 and code in {"DEM", "DEP", "DFP"}:
                quantity = _d(capacity_kw)

        if quantity <= 0 and code != "CFI":
            continue

        amount = quantity * rate
        total += amount
        components.append({
            "code": code,
            "description": f"{line.get('description') or code} · {target_voltage}",
            "quantity": float(quantity),
            "unit_price": float(rate),
            "net_amount": float(amount.quantize(Decimal("0.01"))),
        })

    # Si la tarifa destino tiene cargo fijo y la factura origen no lo discriminó,
    # lo agregamos porque forma parte de la tarifa oficial destino.
    if "CFI" in rates and "CFI" not in used_codes:
        rate = _d(rates["CFI"])
        total += rate
        components.append({
            "code": "CFI",
            "description": f"Cargo fijo · {target_voltage}",
            "quantity": 1.0,
            "unit_price": float(rate),
            "net_amount": float(rate),
        })

    if not components:
        return None, [], schedule

    return total.quantize(Decimal("0.01")), components, schedule


def _proposed_t4_components(rates_rows, invoice, tariff, voltage, capacity_kw):
    """Simula T4 con DEM + ECO (+ CFI/CAV si existen)."""
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


def _scenario_for_history(history, selected):
    """
    Devuelve el escenario recomendado para el período seleccionado.

    Prioridad:
    1) si está en BT => BT→MT
    2) si está en MT/AT y cumple 12/12 >=100 kW => T4
    """
    meter = selected.get("meters") or {}
    tariff = _tariff_key(selected.get("current_tariff_code") or meter.get("current_tariff_code"))
    voltage = _voltage_key(selected.get("voltage_level") or meter.get("voltage_level"))

    period = _period(selected)
    last12 = [x for x in history if _period(x) <= period][-12:]
    max_any_12 = max([_max_demand(x) for x in last12] or [Decimal("0")])
    months_over_100 = sum(1 for x in last12 if _max_demand(x) >= Decimal("100"))

    if voltage == "BT" and tariff in {"T2", "T3", "T3A"}:
        if max_any_12 >= Decimal("300"):
            status = "strong"
        elif max_any_12 >= Decimal("100"):
            status = "candidate"
        elif max_any_12 >= Decimal("50"):
            status = "preliminary"
        else:
            status = "not_candidate"

        if status != "not_candidate":
            return {
                "mode": "mt",
                "status": status,
                "current_label": f"{tariff}-BT",
                "recommended_label": f"{tariff}-MT",
                "target_tariff": tariff,
                "target_voltage": "MT",
                "requires_epen_feasibility": True,
                "months_over_100kw_last12": months_over_100,
                "max_demand_12m_kw": float(max_any_12),
            }

    if (
        voltage in {"MT", "AT"}
        and tariff in {"T3", "T3A"}
        and len(last12) >= 12
        and months_over_100 == 12
    ):
        return {
            "mode": "t4",
            "status": "candidate",
            "current_label": f"{tariff}-{voltage}",
            "recommended_label": f"T4-{voltage}",
            "target_tariff": f"T4-{voltage}",
            "target_voltage": voltage,
            "requires_epen_contract": True,
            "months_over_100kw_last12": months_over_100,
            "max_demand_12m_kw": float(max_any_12),
        }

    return {
        "mode": "none",
        "status": "not_candidate",
        "current_label": f"{tariff}-{voltage}" if voltage != "NA" else tariff,
        "recommended_label": None,
        "months_over_100kw_last12": months_over_100,
        "max_demand_12m_kw": float(max_any_12),
    }


def _point_for_invoice(rates, history, invoice, scenario):
    period = _period(invoice)
    meter = invoice.get("meters") or {}
    tariff = _tariff_key(invoice.get("current_tariff_code") or meter.get("current_tariff_code"))
    voltage = _voltage_key(invoice.get("voltage_level") or meter.get("voltage_level"))

    peak_kw, off_kw = _contracted(invoice)
    demand = _max_demand(invoice)
    if peak_kw <= 0:
        peak_kw = demand
    capacity_kw = max(peak_kw, off_kw, demand)

    actual_cost, actual_components = _actual_tariff_cost(invoice)

    proposed_cost = None
    proposed_components = []
    schedule = None

    if scenario["mode"] == "mt":
        proposed_cost, proposed_components, schedule = _target_same_tariff_components(
            rates, invoice, tariff, "MT", capacity_kw
        )
        current_label = f"{tariff}-BT"
        recommended_label = f"{tariff}-MT"
    elif scenario["mode"] == "t4":
        target = f"T4-{voltage}"
        proposed_cost, proposed_components, schedule = _proposed_t4_components(
            rates, invoice, target, voltage, capacity_kw
        )
        current_label = f"{tariff}-{voltage}"
        recommended_label = target
    else:
        return None

    available = actual_cost is not None and proposed_cost is not None
    saving = Decimal("0")
    if available:
        saving = max(Decimal("0"), actual_cost - proposed_cost)

    return {
        "billing_period": period,
        "current_tariff": current_label,
        "recommended_tariff": recommended_label,
        "current_cost": None if actual_cost is None else float(actual_cost),
        "recommended_cost": None if proposed_cost is None else float(proposed_cost),
        "monthly_saving": float(saving),
        "annualized_saving": float(saving * 12),
        "capacity_kw": float(capacity_kw),
        "available": available,
        "reason": None if available else (
            "missing_actual_tariff_lines" if actual_cost is None
            else "missing_tariff_schedule"
        ),
        "current_cost_source": "actual_invoice_lines",
        "current_components": actual_components,
        "proposed_components": proposed_components,
        "resolution_number": None if not schedule else schedule.get("resolution_number"),
        "billing_month": None if not schedule else schedule.get("billing_month"),
        "consumption_month": None if not schedule else schedule.get("consumption_month"),
        "scenario": scenario["mode"],
    }


@router.get("/meters/{meter_id}/tariff-saving-history")
def tariff_saving_history(meter_id: str, user: CurrentUser = Depends(current_user)):
    """
    Histórico por medidor:
    - BT: tarifa REAL BT vs misma tarifa simulada en MT.
    - MT/AT elegible: T3/T3A REAL vs T4 simulada.
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
        "meters(id,meter_number,supply_number,service_name,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw)"
    ).eq("meter_id", meter_id).execute().data or []

    invoices = _one_invoice_per_period(invoices)
    if not invoices:
        return {"meter_id": meter_id, "mode": "none", "points": []}

    latest = invoices[-1]
    latest_scenario = _scenario_for_history(invoices, latest)

    if latest_scenario["mode"] == "none":
        return {
            "meter_id": meter_id,
            "mode": "none",
            "status": latest_scenario["status"],
            "current_tariff": latest_scenario["current_label"],
            "recommended_tariff": None,
            "points": [],
        }

    points = []
    for invoice in invoices[-24:]:
        # Para cada período mantenemos el mismo tipo de oportunidad que tiene hoy
        # el suministro. Si en el histórico faltaba nivel de tensión, usamos el
        # nivel del medidor actual para no perder facturas válidas.
        point = _point_for_invoice(rates, invoices, invoice, latest_scenario)
        if point:
            points.append(point)

    return {
        "meter_id": meter_id,
        "mode": latest_scenario["mode"],
        "status": latest_scenario["status"],
        "current_tariff": latest_scenario["current_label"],
        "recommended_tariff": latest_scenario["recommended_label"],
        "months_over_100kw_last12": latest_scenario.get("months_over_100kw_last12"),
        "max_demand_12m_kw": latest_scenario.get("max_demand_12m_kw"),
        "taxes_included": False,
        "current_cost_source": "actual_invoice_lines",
        "formula": "actual_current_tariff_cost - simulated_proposed_tariff_cost",
        "requires_epen_feasibility": latest_scenario.get("requires_epen_feasibility", False),
        "requires_epen_contract": latest_scenario.get("requires_epen_contract", False),
        "points": points,
    }


@router.get("/organizations/{organization_id}/tariff-saving-summary")
def tariff_saving_summary(
    organization_id: str,
    period: str,
    user: CurrentUser = Depends(current_user),
):
    """
    Total mensual del período usando el mismo motor que el detalle individual.
    Incluye:
    - BT→MT
    - T3/T3A→T4
    """
    require_org(user.id, organization_id)
    db = admin_db()
    period = str(period or "")[:7]

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
        "meters(id,meter_number,supply_number,service_name,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw)"
    ).eq("organization_id", organization_id).execute().data or []

    grouped = {}
    for invoice in invoices:
        grouped.setdefault(invoice["meter_id"], []).append(invoice)

    rows = []
    total = Decimal("0")

    for meter_id, history in grouped.items():
        history = _one_invoice_per_period(history)
        if not history:
            continue

        selected = next((x for x in history if _period(x) == period), None)
        if selected is None:
            continue

        scenario = _scenario_for_history(history, selected)
        if scenario["mode"] == "none":
            continue

        point = _point_for_invoice(rates, history, selected, scenario)
        if point is None:
            continue

        meter = selected.get("meters") or {}
        row = {
            "meter_id": meter_id,
            "meter_number": meter.get("meter_number"),
            "supply_number": meter.get("supply_number"),
            "service_name": meter.get("service_name"),
            **point,
        }
        rows.append(row)

        if point["available"]:
            total += Decimal(str(point["monthly_saving"]))

    return {
        "billing_period": period,
        "monthly_saving": float(total),
        "annualized_saving": float(total * 12),
        "candidate_count": len(rows),
        "valued_count": sum(1 for row in rows if row["available"]),
        "meters": rows,
        "methodology": "actual_current_tariff_cost - simulated_proposed_tariff_cost",
        "taxes_included": False,
    }
