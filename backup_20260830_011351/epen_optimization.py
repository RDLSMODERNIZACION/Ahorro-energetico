from collections import defaultdict
from decimal import Decimal, InvalidOperation
from fastapi import APIRouter, Depends

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db

router = APIRouter(tags=["Optimización EPEN"])
ZERO = Decimal("0")


def _d(value):
    try:
        return Decimal(str(value or 0))
    except (InvalidOperation, ValueError, TypeError):
        return ZERO


def _tariff_key(value):
    return (value or "").upper().strip()


def _voltage_key(value):
    value = (value or "").upper().strip()
    if value in {"BT", "BAJA", "BAJA TENSION", "BAJA TENSIÓN"}:
        return "BT"
    if value in {"MT", "MEDIA", "MEDIA TENSION", "MEDIA TENSIÓN"}:
        return "MT"
    if value in {"AT", "ALTA", "ALTA TENSION", "ALTA TENSIÓN"}:
        return "AT"
    return "NA"


def _period(invoice):
    return str(invoice.get("billing_period") or invoice.get("period_start") or "")[:7]


def _measurements(invoice):
    return invoice.get("invoice_measurements") or []


def _active_kwh(invoice):
    return sum((_d(x.get("active_energy_kwh")) for x in _measurements(invoice)), ZERO)


def _max_demand(invoice):
    values = []
    for row in _measurements(invoice):
        values.extend([
            _d(row.get("demand_kw")),
            _d(row.get("registered_demand_peak_kw")),
            _d(row.get("registered_demand_off_peak_kw")),
        ])
    return max(values or [ZERO])


def _band_demands(invoice):
    peak = max([_d(x.get("registered_demand_peak_kw")) for x in _measurements(invoice)] or [ZERO])
    off = max([_d(x.get("registered_demand_off_peak_kw")) for x in _measurements(invoice)] or [ZERO])
    return peak, off


def _line_capacity(invoice, code):
    values = [
        _d(x.get("quantity"))
        for x in (invoice.get("invoice_lines") or [])
        if (x.get("concept_code") or "").upper() == code and _d(x.get("quantity")) > 0
    ]
    return max(values or [ZERO])


def _contracted(invoice):
    meter = invoice.get("meters") or {}
    peak = _d(invoice.get("contracted_kw_peak") or meter.get("contracted_kw_peak"))
    off = _d(invoice.get("contracted_kw_off_peak") or meter.get("contracted_kw_off_peak"))
    if peak <= 0:
        peak = _line_capacity(invoice, "DEP") or _line_capacity(invoice, "DEM")
    if off <= 0:
        off = _line_capacity(invoice, "DFP")
    if peak <= 0:
        peak = _d(invoice.get("service_capacity_kw") or meter.get("service_capacity_kw"))
    # Si no hay capacidad fuera de punta explícita no la inventamos para el diagnóstico T3.
    return peak, off


def _rate_set(rows, period, tariff, voltage, capacity):
    tariff = _tariff_key(tariff)
    voltage = _voltage_key(voltage)
    selected = []
    schedule = None
    for row in rows:
        category = row.get("tariff_categories") or {}
        calendar = row.get("tariff_schedules") or {}
        if _tariff_key(category.get("code")) != tariff:
            continue
        billing_month = str(calendar.get("billing_month") or "")[:7]
        consumption_month = str(calendar.get("consumption_month") or "")[:7]
        if billing_month:
            if billing_month != period:
                continue
        elif consumption_month and consumption_month != period:
            continue
        row_voltage = _voltage_key(row.get("voltage_level"))
        if row_voltage not in {"NA", voltage}:
            continue
        min_kw = _d(row.get("min_capacity_kw"))
        max_kw = row.get("max_capacity_kw")
        if capacity < min_kw:
            continue
        if max_kw is not None and capacity >= _d(max_kw):
            continue
        selected.append(row)
        schedule = calendar
    if not selected:
        return None, None
    rates = {(x.get("charge_code") or "").upper(): _d(x.get("unit_price")) for x in selected}
    return rates, schedule


def _simulate(rows, invoice, tariff, voltage, peak_kw, off_peak_kw=None):
    period = _period(invoice)
    active = _active_kwh(invoice)
    capacity_for_band = max(_d(peak_kw), _d(off_peak_kw))
    rates, schedule = _rate_set(rows, period, tariff, voltage, capacity_for_band)
    if not rates:
        return None, schedule

    peak_kw = _d(peak_kw)
    off_peak_kw = _d(off_peak_kw)
    cost = rates.get("CFI", ZERO)
    cost += rates.get("DEM", ZERO) * peak_kw
    cost += rates.get("DEP", ZERO) * peak_kw
    if "DFP" in rates:
        cost += rates["DFP"] * (off_peak_kw if off_peak_kw > 0 else peak_kw)

    bands = defaultdict(Decimal)
    for m in _measurements(invoice):
        band = (m.get("time_band") or "all").lower()
        bands[band] += _d(m.get("active_energy_kwh"))

    if any(code in rates for code in ("EPI", "ERE", "EVA")):
        band_total = bands["peak"] + bands["remaining"] + bands["valley"]
        if band_total > 0:
            cost += bands["peak"] * rates.get("EPI", ZERO)
            cost += bands["remaining"] * rates.get("ERE", ZERO)
            cost += bands["valley"] * rates.get("EVA", ZERO)
        else:
            energy_rates = [rates[x] for x in ("EPI", "ERE", "EVA") if x in rates]
            if energy_rates:
                cost += active * (sum(energy_rates, ZERO) / Decimal(len(energy_rates)))
    else:
        cost += active * rates.get("ECO", ZERO)

    if "CAV" in rates:
        cost += active * rates["CAV"]
    return cost.quantize(Decimal("0.01")), schedule


def _f(value):
    return float(_d(value))


def _positive_saving(current_cost, proposed_cost):
    if current_cost is None or proposed_cost is None:
        return None
    return max(ZERO, current_cost - proposed_cost).quantize(Decimal("0.01"))


@router.get("/organizations/{organization_id}/epen-optimization")
def epen_optimization(organization_id: str, user: CurrentUser = Depends(current_user)):
    """Analiza tres oportunidades EPEN: T3 punta/fuera de punta, T3→T4 y BT→MT.

    Los ahorros se expresan antes de impuestos para no aplicar una alícuota fiscal fija incorrecta.
    Los cambios T4 y BT→MT son simulaciones tarifarias y requieren factibilidad/aceptación de EPEN.
    """
    require_org(user.id, organization_id)
    db = admin_db()

    rates = db.table("tariff_rates").select(
        "unit_price,voltage_level,min_capacity_kw,max_capacity_kw,min_consumption_kwh,max_consumption_kwh,"
        "charge_code,time_band,tariff_categories(code),"
        "tariff_schedules(resolution_number,consumption_month,billing_month,valid_from,valid_to)"
    ).execute().data or []

    invoices = db.table("invoices").select(
        "id,meter_id,billing_period,period_start,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw,total_amount,net_taxable,"
        "meters(id,meter_number,tracking_code,supply_number,service_name,current_tariff_code,voltage_level,"
        "contracted_kw_peak,contracted_kw_off_peak,service_capacity_kw,t4_candidate,t4_validation_status,"
        "mt_candidate,mt_feasibility_status,mt_estimated_investment),"
        "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,"
        "registered_demand_off_peak_kw,time_band),"
        "invoice_lines(concept_code,quantity,unit_price,net_amount)"
    ).eq("organization_id", organization_id).execute().data or []

    grouped = defaultdict(list)
    for invoice in invoices:
        grouped[invoice["meter_id"]].append(invoice)

    rows = []
    total_t3 = ZERO
    total_t4 = ZERO
    total_mt = ZERO
    count_t3 = count_t4 = count_mt = 0

    for meter_id, history in grouped.items():
        history.sort(key=lambda x: _period(x), reverse=True)
        latest = history[0]
        latest_period = _period(latest)
        meter = latest.get("meters") or {}
        tariff = _tariff_key(latest.get("current_tariff_code") or meter.get("current_tariff_code"))
        voltage = _voltage_key(latest.get("voltage_level") or meter.get("voltage_level"))
        current_peak, current_off = _contracted(latest)
        latest_demand = _max_demand(latest)
        active = _active_kwh(latest)

        last12 = history[:12]
        band_peaks = [_band_demands(x)[0] for x in last12 if _band_demands(x)[0] > 0]
        band_offs = [_band_demands(x)[1] for x in last12 if _band_demands(x)[1] > 0]
        max_peak_12 = max(band_peaks or [ZERO])
        max_off_12 = max(band_offs or [ZERO])
        max_any_12 = max([_max_demand(x) for x in last12] or [ZERO])

        # 1) T3: capacidades punta / fuera de punta.
        is_t3 = tariff in {"T3", "T3A"}
        t3_status = "not_t3"
        t3_current_cost = t3_optimized_cost = t3_saving = None
        recommended_peak = max_peak_12
        recommended_off = max_off_12
        if is_t3:
            if current_peak <= 0 or current_off <= 0:
                t3_status = "missing_contracted_bands"
            elif recommended_peak <= 0 or recommended_off <= 0:
                t3_status = "missing_registered_band_demands"
            else:
                t3_status = "candidate" if recommended_peak < current_peak or recommended_off < current_off else "optimized"
                t3_current_cost, _ = _simulate(rates, latest, tariff, voltage, current_peak, current_off)
                t3_optimized_cost, _ = _simulate(
                    rates, latest, tariff, voltage,
                    min(current_peak, recommended_peak),
                    min(current_off, recommended_off),
                )
                t3_saving = _positive_saving(t3_current_cost, t3_optimized_cost)
                if t3_saving and t3_saving > 0:
                    count_t3 += 1
                    total_t3 += t3_saving

        # 2) T4: MT/AT + al menos 12 períodos y demanda >=100 kW en cada uno.
        months_over_100 = sum(1 for x in last12 if _max_demand(x) >= Decimal("100"))
        if voltage not in {"MT", "AT"}:
            t4_status = "requires_mt"
        elif len(last12) < 12:
            t4_status = "insufficient_history"
        elif months_over_100 == 12:
            t4_status = "candidate"
        else:
            t4_status = "not_eligible_history"

        t4_tariff = "T4-MT" if voltage == "MT" else "T4-AT" if voltage == "AT" else None
        current_t3_cost = None
        t4_cost = None
        t4_optimized_cost = None
        t4_saving = None
        t4_optimized_saving = None
        if t4_tariff and tariff in {"T3", "T3A"}:
            peak_for_current = current_peak if current_peak > 0 else max_any_12
            off_for_current = current_off if current_off > 0 else peak_for_current
            unique_capacity = max(peak_for_current, off_for_current)
            current_t3_cost, _ = _simulate(rates, latest, tariff, voltage, peak_for_current, off_for_current)
            t4_cost, _ = _simulate(rates, latest, t4_tariff, voltage, unique_capacity, ZERO)
            t4_saving = _positive_saving(current_t3_cost, t4_cost)
            optimized_unique = max_any_12 if max_any_12 > 0 else unique_capacity
            t4_optimized_cost, _ = _simulate(rates, latest, t4_tariff, voltage, optimized_unique, ZERO)
            t4_optimized_saving = _positive_saving(current_t3_cost, t4_optimized_cost)
            if t4_status == "candidate" and t4_saving and t4_saving > 0:
                count_t4 += 1
                total_t4 += t4_saving

        # 3) BT→MT: misma categoría y capacidades, valorizada con cuadro MT del mismo período.
        if voltage == "BT" and max_any_12 >= Decimal("300"):
            mt_level = "strong"
        elif voltage == "BT" and max_any_12 >= Decimal("100"):
            mt_level = "candidate"
        elif voltage == "BT" and max_any_12 >= Decimal("50"):
            mt_level = "preliminary"
        else:
            mt_level = "not_candidate"

        bt_cost = mt_cost = mt_saving = None
        if voltage == "BT" and tariff in {"T2", "T3", "T3A"}:
            peak_for_voltage = current_peak if current_peak > 0 else max_any_12
            off_for_voltage = current_off if current_off > 0 else peak_for_voltage
            bt_cost, _ = _simulate(rates, latest, tariff, "BT", peak_for_voltage, off_for_voltage)
            mt_cost, _ = _simulate(rates, latest, tariff, "MT", peak_for_voltage, off_for_voltage)
            mt_saving = _positive_saving(bt_cost, mt_cost)
            if mt_level in {"strong", "candidate", "preliminary"} and mt_saving and mt_saving > 0:
                count_mt += 1
                total_mt += mt_saving

        investment = _d(meter.get("mt_estimated_investment"))
        payback = None
        if investment > 0 and mt_saving and mt_saving > 0:
            payback = (investment / mt_saving).quantize(Decimal("0.1"))

        rows.append({
            "meter_id": meter_id,
            "meter_number": meter.get("meter_number"),
            "tracking_code": meter.get("tracking_code"),
            "supply_number": meter.get("supply_number"),
            "service_name": meter.get("service_name"),
            "period": latest_period,
            "current_tariff": tariff,
            "voltage_level": voltage,
            "consumption_kwh": _f(active),
            "latest_max_demand_kw": _f(latest_demand),
            "max_demand_12m_kw": _f(max_any_12),
            "periods_available": len(history),
            "t3": {
                "status": t3_status,
                "current_peak_kw": _f(current_peak),
                "current_off_peak_kw": _f(current_off),
                "max_registered_peak_12m_kw": _f(max_peak_12),
                "max_registered_off_peak_12m_kw": _f(max_off_12),
                "recommended_peak_kw": _f(min(current_peak, recommended_peak) if current_peak > 0 and recommended_peak > 0 else recommended_peak),
                "recommended_off_peak_kw": _f(min(current_off, recommended_off) if current_off > 0 and recommended_off > 0 else recommended_off),
                "current_cost_before_taxes": _f(t3_current_cost) if t3_current_cost is not None else None,
                "optimized_cost_before_taxes": _f(t3_optimized_cost) if t3_optimized_cost is not None else None,
                "monthly_saving_before_taxes": _f(t3_saving) if t3_saving is not None else None,
                "annual_saving_before_taxes": _f(t3_saving * 12) if t3_saving is not None else None,
            },
            "t4": {
                "status": t4_status,
                "target_tariff": t4_tariff,
                "months_over_100kw_last12": months_over_100,
                "current_t3_cost_before_taxes": _f(current_t3_cost) if current_t3_cost is not None else None,
                "t4_cost_before_taxes": _f(t4_cost) if t4_cost is not None else None,
                "t4_optimized_cost_before_taxes": _f(t4_optimized_cost) if t4_optimized_cost is not None else None,
                "monthly_saving_before_taxes": _f(t4_saving) if t4_saving is not None else None,
                "optimized_monthly_saving_before_taxes": _f(t4_optimized_saving) if t4_optimized_saving is not None else None,
                "annual_saving_before_taxes": _f(t4_saving * 12) if t4_saving is not None else None,
                "requires_epen_contract": True,
            },
            "mt": {
                "status": mt_level,
                "current_bt_cost_before_taxes": _f(bt_cost) if bt_cost is not None else None,
                "simulated_mt_cost_before_taxes": _f(mt_cost) if mt_cost is not None else None,
                "monthly_saving_before_taxes": _f(mt_saving) if mt_saving is not None else None,
                "annual_saving_before_taxes": _f(mt_saving * 12) if mt_saving is not None else None,
                "estimated_investment": _f(investment) if investment > 0 else None,
                "payback_months": _f(payback) if payback is not None else None,
                "requires_epen_feasibility": True,
            },
        })

    rows.sort(
        key=lambda x: max(
            x["t3"].get("monthly_saving_before_taxes") or 0,
            x["t4"].get("monthly_saving_before_taxes") or 0,
            x["mt"].get("monthly_saving_before_taxes") or 0,
        ),
        reverse=True,
    )
    latest_period = max([x["period"] for x in rows if x.get("period")] or [""])
    return {
        "period": latest_period,
        "taxes_included": False,
        "note": "Simulaciones antes de impuestos. T4 y BT→MT requieren validación/factibilidad de EPEN.",
        "summary": {
            "t3_candidates": count_t3,
            "t4_candidates": count_t4,
            "mt_candidates": count_mt,
            "t3_monthly_saving_before_taxes": _f(total_t3),
            "t4_monthly_saving_before_taxes": _f(total_t4),
            "mt_monthly_saving_before_taxes": _f(total_mt),
        },
        "meters": rows,
    }

@router.get("/meters/{meter_id}/epen-optimization")
def meter_epen_optimization(meter_id: str, user: CurrentUser = Depends(current_user)):
    """Devuelve el diagnóstico EPEN avanzado de un solo medidor."""
    db = admin_db()
    meter_rows = db.table("meters").select("id,organization_id").eq("id", meter_id).limit(1).execute().data or []
    if not meter_rows:
        return {"meter": None}
    organization_id = meter_rows[0]["organization_id"]
    require_org(user.id, organization_id)
    result = epen_optimization(organization_id, user)
    row = next((x for x in result.get("meters", []) if x.get("meter_id") == meter_id), None)
    return {"meter": row, "period": result.get("period"), "taxes_included": False}
