from __future__ import annotations

from collections import defaultdict
from datetime import date
from math import sqrt
from statistics import mean

from fastapi import APIRouter, Depends, Query

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db

router = APIRouter(tags=["Alumbrado público"])


def _num(value):
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _month_key(value) -> str:
    if value is None:
        return ""
    return str(value)[:7]


def _period_date(period: str) -> date:
    year, month = period.split("-")
    return date(int(year), int(month), 1)


def _month_index(period: str) -> int:
    d = _period_date(period)
    return d.year * 12 + d.month


def _invoice_kwh(invoice: dict) -> float | None:
    values = [
        _num(x.get("active_energy_kwh"))
        for x in (invoice.get("invoice_measurements") or [])
        if _num(x.get("active_energy_kwh")) is not None
    ]
    return sum(values) if values else None


def _invoice_demand(invoice: dict) -> float | None:
    values = []
    for measurement in invoice.get("invoice_measurements") or []:
        for key in ("demand_kw", "registered_demand_peak_kw", "registered_demand_off_peak_kw"):
            value = _num(measurement.get(key))
            if value is not None and value > 0:
                values.append(value)
    return max(values) if values else None


def _invoice_power_factor(invoice: dict) -> tuple[float | None, bool]:
    lines = invoice.get("invoice_lines") or []
    cos_charge = sum(
        max(0.0, _num(line.get("net_amount")) or 0.0)
        for line in lines
        if str(line.get("concept_code") or "").upper().strip() == "COS"
    )

    resolved = []
    penalized = cos_charge > 0

    for measurement in invoice.get("invoice_measurements") or []:
        reported = _num(measurement.get("power_factor"))
        tangent = _num(measurement.get("tangent_phi"))
        surcharge = _num(measurement.get("reactive_surcharge_percent")) or 0.0

        if reported is not None and reported > 0:
            resolved.append(reported)
        elif tangent is not None and tangent > 0:
            resolved.append(1.0 / sqrt(1.0 + tangent * tangent))

        if surcharge > 0:
            penalized = True

    return (min(resolved) if resolved else None, penalized)


def _reading_is_coherent(invoice: dict) -> bool | None:
    previous = _num(invoice.get("reading_previous"))
    current = _num(invoice.get("reading_current"))
    multiplier = _num(invoice.get("multiplier"))
    kwh = _num(invoice.get("active_energy_kwh"))
    if previous is None or current is None or multiplier is None or kwh is None:
        return None
    expected = (current - previous) * multiplier
    tolerance = max(1.0, abs(kwh) * 0.01)
    return abs(expected - kwh) <= tolerance


def _measurement_profile(history: list[dict]) -> dict:
    verified = [x for x in history if _reading_is_coherent(x) is not None]
    coherent = sum(1 for x in verified if _reading_is_coherent(x) is True)
    incoherent = sum(1 for x in verified if _reading_is_coherent(x) is False)

    if not verified:
        code = "SIN_EVIDENCIA"
        label = "Sin evidencia"
        detail = "No hay lecturas verificables cargadas"
    elif incoherent == len(verified) and len(verified) >= 3:
        code = "ESTIMADO_PROBABLE"
        label = "Estimado probable"
        detail = f"0 de {len(verified)} períodos coinciden con diferencia de lecturas"
    elif incoherent > 0:
        code = "MEDIDO_CON_ANOMALIAS"
        label = "Medido con anomalías"
        detail = f"{coherent} de {len(verified)} períodos coherentes; {incoherent} a revisar"
    else:
        code = "MEDIDO_CONFIRMADO"
        label = "Medido confirmado"
        detail = f"{coherent} períodos coherentes con lecturas"

    return {
        "code": code,
        "label": label,
        "detail": detail,
        "verified_periods": len(verified),
        "coherent_periods": coherent,
        "incoherent_periods": incoherent,
    }


def _analysis_status(current_kwh, previous_kwh, avg_kwh, tariff_code, validation_status, history_values):
    reasons = []
    level = "normal"

    change_pct = None
    if current_kwh is not None and previous_kwh not in (None, 0):
        change_pct = (current_kwh - previous_kwh) / previous_kwh * 100.0

    if current_kwh == 0 and (avg_kwh or 0) >= 300:
        reasons.append("Consumo cero con histórico significativo")
        level = "critical"
    elif change_pct is not None and abs(change_pct) >= 100:
        reasons.append(f"Variación mensual {change_pct:+.0f}%")
        level = "critical"
    elif change_pct is not None and abs(change_pct) >= 50:
        reasons.append(f"Variación mensual {change_pct:+.0f}%")
        level = "warning"

    vals = [v for v in history_values[-6:] if v is not None]
    constant = False
    if len(vals) >= 4 and mean(vals) > 100:
        spread = max(vals) - min(vals)
        constant = spread <= max(20.0, mean(vals) * 0.01)
        if constant:
            reasons.append("Consumo casi constante: revisar si es estimado")
            if level == "normal":
                level = "warning"

    if tariff_code and tariff_code != "T1AP":
        reasons.append(f"Tarifa informada {tariff_code}, distinta de T1AP")
        if level == "normal":
            level = "warning"

    if validation_status == "warning":
        reasons.append("Factura marcada para revisión")
        if level == "normal":
            level = "warning"

    return level, reasons, change_pct, constant


@router.get("/organizations/{organization_id}/public-lighting/analysis")
def public_lighting_analysis(
    organization_id: str,
    billing_period: str | None = Query(None, pattern=r"^\d{4}-\d{2}$"),
    search: str | None = None,
    user: CurrentUser = Depends(current_user),
):
    require_org(user.id, organization_id)
    db = admin_db()

    ap_meters = (
        db.table("public_lighting_meters")
        .select(
            "id,linked_meter_id,supply_number,supply_contract,meter_number,address,"
            "tariff_code,validation_status,billing_type,voltage_level"
        )
        .eq("organization_id", organization_id)
        .order("supply_number")
        .execute()
        .data
        or []
    )

    general_meters = (
        db.table("meters")
        .select(
            "id,meter_number,supply_number,service_name,current_tariff_code,"
            "voltage_level,contracted_kw_peak,contracted_kw_off_peak"
        )
        .eq("organization_id", organization_id)
        .execute()
        .data
        or []
    )
    general_by_id = {m["id"]: m for m in general_meters}

    linked_ids = list({x.get("linked_meter_id") for x in ap_meters if x.get("linked_meter_id")})
    ap_ids = [x["id"] for x in ap_meters]

    invoices = []
    if linked_ids:
        page_size = 1000
        offset = 0
        while True:
            page = (
                db.table("invoices")
                .select(
                    "id,meter_id,invoice_number,billing_period,period_start,period_end,"
                    "issue_date,due_date,current_tariff_code,tariff_name,tariff_class,"
                    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,total_amount,"
                    "amount_due,vat_amount,previous_debt_amount,"
                    "invoice_measurements(active_energy_kwh,reactive_energy_kvarh,demand_kw,"
                    "power_factor,registered_demand_peak_kw,registered_demand_off_peak_kw,"
                    "tangent_phi,reactive_surcharge_percent,meter_number,measurement_type),"
                    "invoice_lines(concept_code,description,quantity,unit_price,net_amount)"
                )
                .eq("organization_id", organization_id)
                .in_("meter_id", linked_ids)
                .order("period_start")
                .order("id")
                .range(offset, offset + page_size - 1)
                .execute()
                .data
                or []
            )
            invoices.extend(page)
            if len(page) < page_size:
                break
            offset += page_size

    ap_invoices = []
    if ap_ids:
        page_size = 1000
        offset = 0
        while True:
            page = (
                db.table("public_lighting_invoices")
                .select(
                    "id,public_lighting_meter_id,invoice_number,billing_period,meter_number,"
                    "active_energy_kwh,reading_previous,reading_current,multiplier,total_amount,metadata"
                )
                .eq("organization_id", organization_id)
                .in_("public_lighting_meter_id", ap_ids)
                .order("billing_period")
                .order("id")
                .range(offset, offset + page_size - 1)
                .execute()
                .data
                or []
            )
            ap_invoices.extend(page)
            if len(page) < page_size:
                break
            offset += page_size

    periods = sorted(
        {_month_key(x.get("billing_period") or x.get("period_start")) for x in invoices if x.get("billing_period") or x.get("period_start")},
        reverse=True,
    )
    selected = billing_period or (periods[0] if periods else date.today().strftime("%Y-%m"))

    invoices_by_meter = defaultdict(list)
    for inv in invoices:
        invoices_by_meter[inv["meter_id"]].append(inv)

    ap_invoices_by_meter = defaultdict(list)
    for inv in ap_invoices:
        ap_invoices_by_meter[inv["public_lighting_meter_id"]].append(inv)

    rows = []
    received = 0
    total_kwh = 0.0
    total_amount = 0.0
    warning_count = 0
    critical_count = 0
    anomaly_count = 0
    measurement_counts = defaultdict(int)

    for ap in ap_meters:
        meter_id = ap.get("linked_meter_id")
        meter = general_by_id.get(meter_id) if meter_id else None

        history = sorted(invoices_by_meter.get(meter_id, []), key=lambda x: _month_key(x.get("billing_period") or x.get("period_start")))
        by_period = {_month_key(x.get("billing_period") or x.get("period_start")): x for x in history}
        current = by_period.get(selected)

        ap_history = sorted(ap_invoices_by_meter.get(ap["id"], []), key=lambda x: _month_key(x.get("billing_period")))
        ap_by_period = {_month_key(x.get("billing_period")): x for x in ap_history}
        current_ap = ap_by_period.get(selected)
        measurement = _measurement_profile(ap_history)
        measurement_counts[measurement["code"]] += 1

        selected_index = _month_index(selected)
        prior = [
            inv for inv in history
            if _month_key(inv.get("billing_period") or inv.get("period_start"))
            and _month_index(_month_key(inv.get("billing_period") or inv.get("period_start"))) < selected_index
        ]
        prior12 = prior[-12:]
        prior_values = [_invoice_kwh(x) for x in prior12]
        prior_values_clean = [x for x in prior_values if x is not None]
        avg12 = mean(prior_values_clean) if prior_values_clean else None
        previous_kwh = _invoice_kwh(prior[-1]) if prior else None

        current_kwh = _invoice_kwh(current) if current else None
        current_amount = _num(current.get("total_amount")) if current else None
        current_demand = _invoice_demand(current) if current else None
        current_pf, current_pf_penalized = _invoice_power_factor(current) if current else (None, False)

        tariff_code = (current or {}).get("current_tariff_code") or (meter or {}).get("current_tariff_code") or ap.get("tariff_code")
        validation_status = ap.get("validation_status")

        if current:
            received += 1
            total_kwh += current_kwh or 0
            total_amount += current_amount or 0
            level, reasons, change_pct, constant = _analysis_status(
                current_kwh, previous_kwh, avg12, tariff_code, validation_status,
                [_invoice_kwh(x) for x in history if _month_index(_month_key(x.get("billing_period") or x.get("period_start"))) <= selected_index],
            )
            if current_pf_penalized:
                reasons.append("Penalización de factor de potencia detectada")
                if level == "normal":
                    level = "warning"
        else:
            level = "missing"
            reasons = ["Sin factura general vinculada para el período seleccionado" if meter_id else "Suministro de Alumbrado Público sin linked_meter_id"]
            change_pct = None
            constant = False

        if measurement["code"] == "ESTIMADO_PROBABLE":
            reasons.insert(0, "Consumo facturado no coincide con diferencia de lecturas en ningún período verificado")
            if level in ("normal", "warning"):
                level = "critical"
        elif measurement["code"] == "MEDIDO_CON_ANOMALIAS":
            reasons.insert(0, measurement["detail"])
            if level == "normal":
                level = "warning"

        if level == "warning":
            warning_count += 1
            anomaly_count += 1
        elif level == "critical":
            critical_count += 1
            anomaly_count += 1

        history_rows = []
        for x in history[-24:]:
            pf_value, pf_penalized = _invoice_power_factor(x)
            history_rows.append({
                "invoice_id": x.get("id"),
                "billing_period": _month_key(x.get("billing_period") or x.get("period_start")),
                "active_energy_kwh": _invoice_kwh(x),
                "demand_kw": _invoice_demand(x),
                "power_factor": round(pf_value, 6) if pf_value is not None else None,
                "power_factor_penalized": pf_penalized,
                "total_amount": _num(x.get("total_amount")),
                "tariff_code": x.get("current_tariff_code"),
                "invoice_number": x.get("invoice_number"),
            })

        reading_previous = _num((current_ap or {}).get("reading_previous"))
        reading_current = _num((current_ap or {}).get("reading_current"))
        reading_multiplier = _num((current_ap or {}).get("multiplier"))
        reading_kwh = _num((current_ap or {}).get("active_energy_kwh"))
        reading_coherent = _reading_is_coherent(current_ap) if current_ap else None

        rows.append({
            "public_lighting_meter_id": ap["id"],
            "meter_id": meter_id,
            "linked": bool(meter_id),
            "supply_number": (meter or {}).get("supply_number") or ap.get("supply_number"),
            "supply_contract": ap.get("supply_contract"),
            "meter_number": (meter or {}).get("meter_number") or ap.get("meter_number"),
            "address": ap.get("address") or (meter or {}).get("service_name"),
            "billing_period": selected,
            "invoice_id": (current or {}).get("id"),
            "invoice_number": (current or {}).get("invoice_number"),
            "active_energy_kwh": current_kwh,
            "demand_kw": current_demand,
            "power_factor": round(current_pf, 6) if current_pf is not None else None,
            "power_factor_penalized": current_pf_penalized,
            "average_12m_kwh": round(avg12, 2) if avg12 is not None else None,
            "previous_kwh": previous_kwh,
            "change_percent": round(change_pct, 1) if change_pct is not None else None,
            "total_amount": current_amount,
            "tariff_code": tariff_code,
            "validation_status": validation_status,
            "analysis_status": level,
            "analysis_reasons": reasons,
            "constant_consumption": constant,
            "measurement_class": measurement["code"],
            "measurement_label": measurement["label"],
            "measurement_detail": measurement["detail"],
            "measurement_verified_periods": measurement["verified_periods"],
            "measurement_coherent_periods": measurement["coherent_periods"],
            "measurement_incoherent_periods": measurement["incoherent_periods"],
            "reading_previous": reading_previous,
            "reading_current": reading_current,
            "reading_multiplier": reading_multiplier,
            "reading_billed_kwh": reading_kwh,
            "reading_coherent": reading_coherent,
            "history": history_rows,
        })

    needle = (search or "").strip().lower()
    if needle:
        rows = [r for r in rows if needle in " ".join(str(v or "").lower() for v in [r.get("supply_number"), r.get("supply_contract"), r.get("meter_number"), r.get("address"), r.get("invoice_number")])]

    order = {"critical": 0, "warning": 1, "missing": 2, "normal": 3}
    rows.sort(key=lambda r: (order.get(r["analysis_status"], 9), -(r.get("active_energy_kwh") or 0)))

    return {
        "billing_period": selected,
        "periods": periods,
        "summary": {
            "expected": len(ap_meters),
            "received": received,
            "missing": max(0, len(ap_meters) - received),
            "unlinked": len([x for x in ap_meters if not x.get("linked_meter_id")]),
            "total_kwh": round(total_kwh, 2),
            "total_amount": round(total_amount, 2),
            "anomalies": anomaly_count,
            "warnings": warning_count,
            "critical": critical_count,
            "measured_confirmed": measurement_counts["MEDIDO_CONFIRMADO"],
            "measured_with_anomalies": measurement_counts["MEDIDO_CON_ANOMALIAS"],
            "estimated_probable": measurement_counts["ESTIMADO_PROBABLE"],
            "measurement_unknown": measurement_counts["SIN_EVIDENCIA"],
        },
        "rows": rows,
    }
