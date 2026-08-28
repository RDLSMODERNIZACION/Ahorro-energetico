from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from typing import Any

from .db import admin_db


def _num(value: Any) -> float:
    try:
        return float(value or 0)
    except Exception:
        return 0.0


def _period(row: dict[str, Any]) -> str:
    return str(row.get("billing_period") or row.get("period_start") or "")[:7]


def _metrics(invoice: dict[str, Any]) -> dict[str, float]:
    measurements = invoice.get("invoice_measurements") or []
    lines = invoice.get("invoice_lines") or []
    meter = invoice.get("meters") or {}

    kwh = sum(_num(m.get("active_energy_kwh")) for m in measurements)
    kvarh = sum(_num(m.get("reactive_energy_kvarh")) for m in measurements)
    demand = max([0.0] + [
        _num(m.get("demand_kw") or m.get("registered_demand_peak_kw"))
        for m in measurements
    ])
    pfs = [_num(m.get("power_factor")) for m in measurements if _num(m.get("power_factor")) > 0]
    pf = min(pfs) if pfs else 0.0
    surcharge = max([0.0] + [_num(m.get("reactive_surcharge_percent")) for m in measurements])
    contracted = _num(invoice.get("contracted_kw_peak") or meter.get("contracted_kw_peak"))

    demand_lines = [x for x in lines if str(x.get("concept_code") or "").upper() in ("DEM", "DEP")]
    power_rate = max([0.0] + [_num(x.get("unit_price")) for x in demand_lines])
    excess = max(0.0, contracted - demand)
    power_saving = excess * power_rate * 1.30 if power_rate > 0 else 0.0

    reactive_lines = [x for x in lines if str(x.get("concept_code") or "").upper() == "COS"]
    reactive_saving = sum(max(0.0, _num(x.get("net_amount"))) for x in reactive_lines) * 1.30

    return {
        "kwh": round(kwh, 3),
        "kvarh": round(kvarh, 3),
        "demand_kw": round(demand, 3),
        "contracted_kw": round(contracted, 3),
        "power_factor": round(pf, 4),
        "reactive_surcharge_percent": round(surcharge, 3),
        "total_amount": round(_num(invoice.get("total_amount")), 2),
        "power_saving": round(power_saving, 2),
        "reactive_saving": round(reactive_saving, 2),
    }


def refresh_energy_intelligence(organization_id: str) -> dict[str, Any]:
    db = admin_db()
    now = datetime.now(timezone.utc).isoformat()

    invoices = (
        db.table("invoices")
        .select(
            "id,meter_id,billing_period,period_start,total_amount,current_tariff_code,"
            "contracted_kw_peak,"
            "meters(id,meter_number,supply_number,service_name,status,current_tariff_code,contracted_kw_peak),"
            "invoice_measurements(active_energy_kwh,reactive_energy_kvarh,demand_kw,"
            "registered_demand_peak_kw,power_factor,reactive_surcharge_percent),"
            "invoice_lines(concept_code,unit_price,net_amount)"
        )
        .eq("organization_id", organization_id)
        .order("billing_period")
        .limit(5000)
        .execute()
        .data
    )

    monthly_map: dict[tuple[str, str], dict[str, Any]] = {}
    for inv in invoices:
        meter_id = str(inv.get("meter_id") or "")
        period = _period(inv)
        if not meter_id or not period:
            continue
        key = (meter_id, period)
        m = _metrics(inv)
        bucket = monthly_map.setdefault(key, {
            "organization_id": organization_id,
            "meter_id": meter_id,
            "period": period,
            "consumption_kwh": 0.0,
            "reactive_kvarh": 0.0,
            "max_demand_kw": 0.0,
            "contracted_kw": 0.0,
            "utilization_percent": 0.0,
            "power_factor": None,
            "reactive_surcharge_percent": 0.0,
            "total_amount": 0.0,
            "tariff_code": inv.get("current_tariff_code") or (inv.get("meters") or {}).get("current_tariff_code"),
            "invoice_count": 0,
            "updated_at": now,
            "_power_saving": 0.0,
            "_reactive_saving": 0.0,
        })
        bucket["consumption_kwh"] += m["kwh"]
        bucket["reactive_kvarh"] += m["kvarh"]
        bucket["max_demand_kw"] = max(bucket["max_demand_kw"], m["demand_kw"])
        bucket["contracted_kw"] = max(bucket["contracted_kw"], m["contracted_kw"])
        if m["power_factor"] > 0:
            bucket["power_factor"] = m["power_factor"] if bucket["power_factor"] is None else min(bucket["power_factor"], m["power_factor"])
        bucket["reactive_surcharge_percent"] = max(bucket["reactive_surcharge_percent"], m["reactive_surcharge_percent"])
        bucket["total_amount"] += m["total_amount"]
        bucket["invoice_count"] += 1
        bucket["_power_saving"] += m["power_saving"]
        bucket["_reactive_saving"] += m["reactive_saving"]

    monthly_rows = []
    private_savings = {}
    for key, row in monthly_map.items():
        contracted = _num(row["contracted_kw"])
        demand = _num(row["max_demand_kw"])
        row["utilization_percent"] = round((demand / contracted * 100) if contracted > 0 else 0, 2)
        private_savings[key] = {
            "power": round(row.pop("_power_saving"), 2),
            "reactive": round(row.pop("_reactive_saving"), 2),
        }
        monthly_rows.append(row)

    if monthly_rows:
        db.table("meter_monthly_metrics").upsert(
            monthly_rows,
            on_conflict="organization_id,meter_id,period",
        ).execute()

    by_meter: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in monthly_rows:
        by_meter[row["meter_id"]].append(row)

    meter_rows = (
        db.table("meters")
        .select("id,status,current_tariff_code,last_seen_period")
        .eq("organization_id", organization_id)
        .execute()
        .data
    )
    meter_meta = {str(x["id"]): x for x in meter_rows}

    snapshot_rows = []
    findings = []

    latest_org_period = max([r["period"] for r in monthly_rows], default="")
    for meter_id, rows in by_meter.items():
        rows = sorted(rows, key=lambda x: x["period"])
        latest = rows[-1]
        last6 = rows[-6:]
        last12 = rows[-12:]
        previous = rows[-2] if len(rows) >= 2 else None

        contracted = _num(latest["contracted_kw"])
        demand = _num(latest["max_demand_kw"])
        excess = max(0.0, contracted - demand)
        utilization = (demand / contracted * 100) if contracted > 0 else 0
        pf = _num(latest.get("power_factor"))
        min_pf_6m = min([_num(x.get("power_factor")) for x in last6 if _num(x.get("power_factor")) > 0], default=0)

        avg6 = sum(_num(x["consumption_kwh"]) for x in last6) / max(1, len(last6))
        avg12 = sum(_num(x["consumption_kwh"]) for x in last12) / max(1, len(last12))
        avg_amount6 = sum(_num(x["total_amount"]) for x in last6) / max(1, len(last6))
        max_demand12 = max([_num(x["max_demand_kw"]) for x in last12], default=0)

        consumption_change = None
        amount_change = None
        if previous and _num(previous["consumption_kwh"]) > 0:
            consumption_change = (_num(latest["consumption_kwh"]) - _num(previous["consumption_kwh"])) / _num(previous["consumption_kwh"]) * 100
        if previous and _num(previous["total_amount"]) > 0:
            amount_change = (_num(latest["total_amount"]) - _num(previous["total_amount"])) / _num(previous["total_amount"]) * 100

        anomaly_score = max(abs(consumption_change or 0), abs(amount_change or 0))
        savings = private_savings.get((meter_id, latest["period"]), {"power": 0, "reactive": 0})
        monthly_saving = savings["power"] + savings["reactive"]

        months_without = 0
        if latest_org_period and latest["period"] < latest_org_period:
            try:
                y1, m1 = map(int, latest["period"].split("-"))
                y2, m2 = map(int, latest_org_period.split("-"))
                months_without = max(0, (y2-y1)*12 + (m2-m1))
            except Exception:
                months_without = 0

        meta = meter_meta.get(meter_id, {})
        snapshot_rows.append({
            "meter_id": meter_id,
            "organization_id": organization_id,
            "latest_period": latest["period"],
            "latest_kwh": round(_num(latest["consumption_kwh"]), 2),
            "avg_kwh_6m": round(avg6, 2),
            "avg_kwh_12m": round(avg12, 2),
            "latest_amount": round(_num(latest["total_amount"]), 2),
            "avg_amount_6m": round(avg_amount6, 2),
            "latest_demand_kw": round(demand, 2),
            "max_demand_12m": round(max_demand12, 2),
            "contracted_kw": round(contracted, 2),
            "excess_kw": round(excess, 2),
            "utilization_percent": round(utilization, 2),
            "power_factor": pf if pf > 0 else None,
            "min_power_factor_6m": min_pf_6m if min_pf_6m > 0 else None,
            "reactive_surcharge_percent": round(_num(latest["reactive_surcharge_percent"]), 2),
            "current_tariff_code": latest.get("tariff_code") or meta.get("current_tariff_code"),
            "months_without_invoice": months_without,
            "status": meta.get("status"),
            "consumption_change_percent": round(consumption_change, 2) if consumption_change is not None else None,
            "amount_change_percent": round(amount_change, 2) if amount_change is not None else None,
            "anomaly_score": round(anomaly_score, 2),
            "monthly_saving_power": round(savings["power"], 2),
            "monthly_saving_reactive": round(savings["reactive"], 2),
            "monthly_saving_tariff": 0,
            "total_monthly_saving": round(monthly_saving, 2),
            "total_annual_saving": round(monthly_saving * 12, 2),
            "updated_at": now,
        })

        if contracted > 0 and excess > 0 and utilization < 85:
            severity = "high" if utilization < 60 else "medium"
            findings.append({
                "organization_id": organization_id,
                "meter_id": meter_id,
                "finding_type": "power_oversizing",
                "severity": severity,
                "title": "Potencia contratada sobredimensionada",
                "diagnosis": f"Utilización de potencia {utilization:.1f}% con {excess:.1f} kW de diferencia.",
                "evidence": {
                    "contracted_kw": round(contracted,2),
                    "max_demand_kw": round(demand,2),
                    "excess_kw": round(excess,2),
                    "utilization_percent": round(utilization,2),
                },
                "recommended_action": "Analizar reducción contractual usando histórico de demanda y margen operativo antes de gestionar ante EPEN.",
                "validation_required": "Confirmar que el máximo de los últimos 12 meses y condiciones de arranque no superen la potencia objetivo.",
                "investment_type": "no_equipment_investment",
                "estimated_monthly_saving": round(savings["power"],2),
                "estimated_annual_saving": round(savings["power"]*12,2),
                "confidence": 0.90 if len(last6) >= 6 else 0.70,
                "status": "open",
                "detected_period": latest["period"],
                "fingerprint": f"{meter_id}:power_oversizing",
                "updated_at": now,
            })

        if 0 < pf < 0.95:
            findings.append({
                "organization_id": organization_id,
                "meter_id": meter_id,
                "finding_type": "low_power_factor",
                "severity": "high" if pf < 0.85 else "medium",
                "title": "Factor de potencia bajo",
                "diagnosis": f"Cos φ {pf:.3f}, por debajo de 0,95.",
                "evidence": {
                    "power_factor": round(pf,4),
                    "reactive_surcharge_percent": round(_num(latest["reactive_surcharge_percent"]),2),
                },
                "recommended_action": "Verificar medición de reactiva y banco existente; dimensionar compensación si corresponde.",
                "validation_required": "Medir carga/reactiva y revisar estado de capacitores antes de definir inversión.",
                "investment_type": "requires_investment",
                "estimated_monthly_saving": round(savings["reactive"],2),
                "estimated_annual_saving": round(savings["reactive"]*12,2),
                "confidence": 0.90,
                "status": "open",
                "detected_period": latest["period"],
                "fingerprint": f"{meter_id}:low_power_factor",
                "updated_at": now,
            })

        if _num(latest["consumption_kwh"]) == 0 and contracted > 0:
            findings.append({
                "organization_id": organization_id,
                "meter_id": meter_id,
                "finding_type": "zero_consumption_with_contract",
                "severity": "high",
                "title": "Consumo nulo con potencia contratada",
                "diagnosis": f"El período {latest['period']} registra 0 kWh y {contracted:.1f} kW contratados.",
                "evidence": {"kwh":0,"contracted_kw":round(contracted,2),"total_amount":round(_num(latest["total_amount"]),2)},
                "recommended_action": "Verificar uso real, lectura/facturación y necesidad de mantener el suministro/potencia.",
                "validation_required": "No confirmar baja sin revisar historial, operación del sitio y situación contractual.",
                "investment_type": "no_equipment_investment",
                "estimated_monthly_saving": 0,
                "estimated_annual_saving": 0,
                "confidence": 0.75,
                "status": "open",
                "detected_period": latest["period"],
                "fingerprint": f"{meter_id}:zero_consumption_with_contract",
                "updated_at": now,
            })

        if anomaly_score >= 30:
            findings.append({
                "organization_id": organization_id,
                "meter_id": meter_id,
                "finding_type": "consumption_anomaly",
                "severity": "high" if anomaly_score >= 60 else "medium",
                "title": "Variación anormal de consumo o importe",
                "diagnosis": f"Cambio máximo intermensual detectado: {anomaly_score:.1f}%.",
                "evidence": {
                    "consumption_change_percent": round(consumption_change,2) if consumption_change is not None else None,
                    "amount_change_percent": round(amount_change,2) if amount_change is not None else None,
                    "latest_kwh": round(_num(latest["consumption_kwh"]),2),
                    "avg_kwh_6m": round(avg6,2),
                },
                "recommended_action": "Revisar causa operativa, estacional, lectura o cambio de régimen antes de asumir ineficiencia.",
                "validation_required": "Comparar con operación del sitio y al menos 6 meses de historial.",
                "investment_type": "unknown",
                "estimated_monthly_saving": 0,
                "estimated_annual_saving": 0,
                "confidence": 0.80 if len(last6) >= 6 else 0.60,
                "status": "open",
                "detected_period": latest["period"],
                "fingerprint": f"{meter_id}:consumption_anomaly",
                "updated_at": now,
            })

    if snapshot_rows:
        db.table("meter_energy_snapshot").upsert(snapshot_rows, on_conflict="meter_id").execute()

    # Cierra hallazgos que ya no aparecen en el nuevo cálculo y luego hace upsert de los activos.
    active_fingerprints = {f["fingerprint"] for f in findings}
    existing = (
        db.table("energy_findings")
        .select("id,fingerprint,status")
        .eq("organization_id", organization_id)
        .eq("status", "open")
        .execute()
        .data
    )
    for row in existing:
        if row.get("fingerprint") not in active_fingerprints:
            db.table("energy_findings").update({
                "status":"resolved",
                "resolved_at":now,
                "updated_at":now,
            }).eq("id", row["id"]).execute()

    if findings:
        db.table("energy_findings").upsert(
            findings,
            on_conflict="organization_id,fingerprint",
        ).execute()

    return {
        "organization_id": organization_id,
        "monthly_metrics": len(monthly_rows),
        "snapshots": len(snapshot_rows),
        "open_findings": len(findings),
        "latest_period": latest_org_period,
    }


def load_energy_knowledge(organization_id: str) -> dict[str, Any]:
    db = admin_db()
    snapshots = (
        db.table("meter_energy_snapshot")
        .select("*,meters(meter_number,supply_number,service_name)")
        .eq("organization_id", organization_id)
        .order("total_annual_saving", desc=True)
        .limit(250)
        .execute()
        .data
    )
    findings = (
        db.table("energy_findings")
        .select("*,meters(meter_number,supply_number,service_name)")
        .eq("organization_id", organization_id)
        .eq("status", "open")
        .order("estimated_annual_saving", desc=True)
        .limit(250)
        .execute()
        .data
    )
    return {
        "snapshots": snapshots,
        "findings": findings,
        "snapshot_count": len(snapshots),
        "finding_count": len(findings),
    }
