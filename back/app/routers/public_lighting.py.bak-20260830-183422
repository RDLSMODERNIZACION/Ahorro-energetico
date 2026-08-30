from __future__ import annotations

from collections import defaultdict
from datetime import date
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

    meters = (
        db.table("public_lighting_meters")
        .select("id,supply_number,supply_contract,meter_number,address,tariff_code,validation_status,billing_type,voltage_level")
        .eq("organization_id", organization_id)
        .order("supply_number")
        .execute()
        .data
        or []
    )

    invoices = (
        db.table("public_lighting_invoices")
        .select("id,public_lighting_meter_id,invoice_number,billing_period,issue_date,meter_number,tariff_code,active_energy_kwh,total_amount,validation_status")
        .eq("organization_id", organization_id)
        .order("billing_period")
        .execute()
        .data
        or []
    )

    periods = sorted({_month_key(x.get("billing_period")) for x in invoices if x.get("billing_period")}, reverse=True)
    selected = billing_period or (periods[0] if periods else date.today().strftime("%Y-%m"))

    by_meter = defaultdict(list)
    for inv in invoices:
        by_meter[inv["public_lighting_meter_id"]].append(inv)

    rows = []
    received = 0
    total_kwh = 0.0
    total_amount = 0.0
    warning_count = 0
    critical_count = 0
    anomaly_count = 0

    for meter in meters:
        history = sorted(by_meter.get(meter["id"], []), key=lambda x: _month_key(x.get("billing_period")))
        by_period = {_month_key(x.get("billing_period")): x for x in history}
        current = by_period.get(selected)

        selected_index = _month_index(selected)
        prior = [
            inv for inv in history
            if _month_key(inv.get("billing_period")) and _month_index(_month_key(inv.get("billing_period"))) < selected_index
        ]
        prior12 = prior[-12:]
        prior_values = [_num(x.get("active_energy_kwh")) for x in prior12]
        prior_values_clean = [x for x in prior_values if x is not None]
        avg12 = mean(prior_values_clean) if prior_values_clean else None
        previous_kwh = _num(prior[-1].get("active_energy_kwh")) if prior else None

        current_kwh = _num(current.get("active_energy_kwh")) if current else None
        current_amount = _num(current.get("total_amount")) if current else None
        tariff_code = (current or {}).get("tariff_code") or meter.get("tariff_code")
        validation_status = (current or {}).get("validation_status") or meter.get("validation_status")

        if current:
            received += 1
            total_kwh += current_kwh or 0
            total_amount += current_amount or 0
            level, reasons, change_pct, constant = _analysis_status(
                current_kwh,
                previous_kwh,
                avg12,
                tariff_code,
                validation_status,
                [_num(x.get("active_energy_kwh")) for x in history if _month_index(_month_key(x.get("billing_period"))) <= selected_index],
            )
        else:
            level = "missing"
            reasons = ["Sin factura para el período seleccionado"]
            change_pct = None
            constant = False

        if level == "warning":
            warning_count += 1
            anomaly_count += 1
        elif level == "critical":
            critical_count += 1
            anomaly_count += 1

        row = {
            "public_lighting_meter_id": meter["id"],
            "supply_number": meter.get("supply_number"),
            "supply_contract": meter.get("supply_contract"),
            "meter_number": (current or {}).get("meter_number") or meter.get("meter_number"),
            "address": meter.get("address"),
            "billing_period": selected,
            "invoice_id": (current or {}).get("id"),
            "invoice_number": (current or {}).get("invoice_number"),
            "active_energy_kwh": current_kwh,
            "average_12m_kwh": round(avg12, 2) if avg12 is not None else None,
            "previous_kwh": previous_kwh,
            "change_percent": round(change_pct, 1) if change_pct is not None else None,
            "total_amount": current_amount,
            "tariff_code": tariff_code,
            "validation_status": validation_status,
            "analysis_status": level,
            "analysis_reasons": reasons,
            "constant_consumption": constant,
            "history": [
                {
                    "billing_period": _month_key(x.get("billing_period")),
                    "active_energy_kwh": _num(x.get("active_energy_kwh")),
                    "total_amount": _num(x.get("total_amount")),
                    "tariff_code": x.get("tariff_code"),
                    "invoice_number": x.get("invoice_number"),
                }
                for x in history[-24:]
            ],
        }
        rows.append(row)

    needle = (search or "").strip().lower()
    if needle:
        rows = [
            r for r in rows
            if needle in " ".join(
                str(v or "").lower()
                for v in [r.get("supply_number"), r.get("supply_contract"), r.get("meter_number"), r.get("address"), r.get("invoice_number")]
            )
        ]

    order = {"critical": 0, "warning": 1, "missing": 2, "normal": 3}
    rows.sort(key=lambda r: (order.get(r["analysis_status"], 9), -(r.get("active_energy_kwh") or 0)))

    return {
        "billing_period": selected,
        "periods": periods,
        "summary": {
            "expected": len(meters),
            "received": received,
            "missing": max(0, len(meters) - received),
            "total_kwh": round(total_kwh, 2),
            "total_amount": round(total_amount, 2),
            "anomalies": anomaly_count,
            "warnings": warning_count,
            "critical": critical_count,
        },
        "rows": rows,
    }
