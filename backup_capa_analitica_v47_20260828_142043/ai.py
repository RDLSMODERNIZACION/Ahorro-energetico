from __future__ import annotations

import json
import os
from datetime import date
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db

router = APIRouter(tags=["IA"])


class AIQuery(BaseModel):
    organization_id: str
    question: str = Field(min_length=2, max_length=1200)


def _period(value: Any) -> str:
    return str(value or "")[:7]


def _num(value: Any) -> float:
    try:
        return float(value or 0)
    except Exception:
        return 0.0


def _invoice_metrics(invoice: dict[str, Any]) -> dict[str, float]:
    measurements = invoice.get("invoice_measurements") or []
    kwh = sum(_num(row.get("active_energy_kwh")) for row in measurements)
    demand = max(
        [0.0]
        + [
            _num(row.get("demand_kw") or row.get("registered_demand_peak_kw"))
            for row in measurements
        ]
    )
    pfs = [_num(row.get("power_factor")) for row in measurements if _num(row.get("power_factor")) > 0]
    pf = min(pfs) if pfs else 0.0

    meter = invoice.get("meters") or {}
    contracted = _num(invoice.get("contracted_kw_peak") or meter.get("contracted_kw_peak"))
    excess = max(0.0, contracted - demand)

    return {
        "kwh": round(kwh, 3),
        "demand_kw": round(demand, 3),
        "contracted_kw": round(contracted, 3),
        "excess_kw": round(excess, 3),
        "power_factor": round(pf, 4),
        "total_amount": round(_num(invoice.get("total_amount")), 2),
    }


def _detect_intent(question: str) -> str:
    q = question.lower()

    if any(x in q for x in ["no se usan", "sin uso", "fuera de uso", "dar de baja", "baja", "sin factur", "inactivo"]):
        return "inactive_supply"
    if any(x in q for x in ["qué hago primero", "que hago primero", "prioridad", "priorizar", "acciones", "mayor ahorro", "mayores ahorros", "conviene hacer"]):
        return "priority"
    if any(x in q for x in ["factor", "cos", "reactiv", "capacitor"]):
        return "power_factor"
    if any(x in q for x in ["potencia", "contratada", "demanda", "sobredimension", "sobrante"]):
        return "power"
    if any(x in q for x in ["anormal", "anómal", "raro", "subió", "subio", "aumentó", "aumento", "variación", "variacion"]):
        return "anomaly"
    if any(x in q for x in ["tarifa", "tarifaria", "encuadram", "epen"]):
        return "tariff"
    if any(x in q for x in ["falt", "pendiente"]):
        return "missing"
    if any(x in q for x in ["consumo", "energía", "energia", "kwh"]):
        return "consumption"
    if any(x in q for x in ["importe", "gasto", "costo", "facturación", "facturacion", "más caro", "mas caro"]):
        return "cost"

    return "general"


def _latest_invoice_rows(db, organization_id: str) -> tuple[str, list[dict[str, Any]]]:
    rows = (
        db.table("invoices")
        .select(
            "id,meter_id,billing_period,period_start,total_amount,current_tariff_code,"
            "contracted_kw_peak,meters(id,meter_number,tracking_code,supply_number,service_name,"
            "contracted_kw_peak,current_tariff_code,voltage_level,status,last_seen_period),"
            "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,power_factor,"
            "reactive_surcharge_percent)"
        )
        .eq("organization_id", organization_id)
        .order("billing_period", desc=True)
        .limit(1500)
        .execute()
        .data
    )
    periods = sorted(
        {
            _period(row.get("billing_period") or row.get("period_start"))
            for row in rows
            if _period(row.get("billing_period") or row.get("period_start"))
        }
    )
    latest = periods[-1] if periods else ""
    return latest, [
        row
        for row in rows
        if _period(row.get("billing_period") or row.get("period_start")) == latest
    ]


def _meter_history_context(db, organization_id: str, periods: list[str]) -> list[dict[str, Any]]:
    if not periods:
        return []

    rows = (
        db.table("invoices")
        .select(
            "meter_id,billing_period,period_start,total_amount,"
            "meters(meter_number,supply_number,service_name,status,last_seen_period),"
            "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,power_factor)"
        )
        .eq("organization_id", organization_id)
        .order("billing_period", desc=True)
        .limit(3000)
        .execute()
        .data
    )

    by_meter: dict[str, dict[str, Any]] = {}
    for inv in rows:
        p = _period(inv.get("billing_period") or inv.get("period_start"))
        if p not in periods:
            continue

        meter_id = str(inv.get("meter_id") or "")
        if not meter_id:
            continue

        meter = inv.get("meters") or {}
        bucket = by_meter.setdefault(
            meter_id,
            {
                "meter_id": meter_id,
                "meter_number": meter.get("meter_number"),
                "supply_number": meter.get("supply_number"),
                "service_name": meter.get("service_name"),
                "status": meter.get("status"),
                "last_seen_period": meter.get("last_seen_period"),
                "months": [],
            },
        )
        m = _invoice_metrics(inv)
        bucket["months"].append(
            {
                "period": p,
                "kwh": m["kwh"],
                "demand_kw": m["demand_kw"],
                "power_factor": m["power_factor"],
                "amount": m["total_amount"],
            }
        )

    result: list[dict[str, Any]] = []
    for row in by_meter.values():
        months = sorted(row["months"], key=lambda x: x["period"])
        if not months:
            continue
        kwhs = [m["kwh"] for m in months]
        amounts = [m["amount"] for m in months]
        latest = months[-1]
        previous = months[-2] if len(months) > 1 else None

        row["months"] = months
        row["latest_kwh"] = latest["kwh"]
        row["latest_amount"] = latest["amount"]
        row["avg_kwh"] = round(sum(kwhs) / len(kwhs), 2)
        row["avg_amount"] = round(sum(amounts) / len(amounts), 2)
        row["kwh_change_percent"] = (
            round((latest["kwh"] - previous["kwh"]) / previous["kwh"] * 100, 1)
            if previous and previous["kwh"] > 0
            else None
        )
        row["amount_change_percent"] = (
            round((latest["amount"] - previous["amount"]) / previous["amount"] * 100, 1)
            if previous and previous["amount"] > 0
            else None
        )
        result.append(row)

    return result


def _build_context(organization_id: str, question: str) -> dict[str, Any]:
    db = admin_db()
    intent = _detect_intent(question)
    latest, invoices = _latest_invoice_rows(db, organization_id)

    enriched = []
    for row in invoices:
        meter = row.get("meters") or {}
        m = _invoice_metrics(row)
        enriched.append(
            {
                "meter_id": row.get("meter_id"),
                "meter_number": meter.get("meter_number"),
                "tracking_code": meter.get("tracking_code"),
                "supply_number": meter.get("supply_number"),
                "service_name": meter.get("service_name"),
                "status": meter.get("status"),
                "last_seen_period": meter.get("last_seen_period"),
                "tariff": row.get("current_tariff_code") or meter.get("current_tariff_code"),
                "voltage_level": meter.get("voltage_level"),
                **m,
            }
        )

    low_pf = sorted(
        [row for row in enriched if 0 < row["power_factor"] < 0.95],
        key=lambda x: x["power_factor"],
    )
    excess = sorted(
        [row for row in enriched if row["excess_kw"] > 0],
        key=lambda x: x["excess_kw"],
        reverse=True,
    )
    top_consumption = sorted(enriched, key=lambda x: x["kwh"], reverse=True)
    top_amount = sorted(enriched, key=lambda x: x["total_amount"], reverse=True)

    missing = (
        db.table("missing_invoice_alerts")
        .select("meter_id,expected_period,message,status,meters(meter_number,tracking_code,supply_number,service_name,status,last_seen_period)")
        .eq("organization_id", organization_id)
        .eq("status", "open")
        .order("expected_period", desc=True)
        .limit(200)
        .execute()
        .data
    )

    opportunities = (
        db.table("opportunities")
        .select("meter_id,title,priority,estimated_annual_saving,estimated_investment,status,meters(meter_number,supply_number,service_name)")
        .eq("organization_id", organization_id)
        .neq("status", "dismissed")
        .order("estimated_annual_saving", desc=True)
        .limit(100)
        .execute()
        .data
    )

    history_rows = (
        db.table("invoices")
        .select(
            "billing_period,period_start,total_amount,"
            "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,power_factor)"
        )
        .eq("organization_id", organization_id)
        .order("billing_period", desc=True)
        .limit(5000)
        .execute()
        .data
    )

    monthly: dict[str, dict[str, float]] = {}
    for inv in history_rows:
        p = _period(inv.get("billing_period") or inv.get("period_start"))
        if not p:
            continue
        bucket = monthly.setdefault(
            p, {"amount": 0.0, "kwh": 0.0, "max_demand_kw": 0.0}
        )
        bucket["amount"] += _num(inv.get("total_amount"))
        measures = inv.get("invoice_measurements") or []
        bucket["kwh"] += sum(_num(m.get("active_energy_kwh")) for m in measures)
        bucket["max_demand_kw"] = max(
            bucket["max_demand_kw"],
            max(
                [0.0]
                + [
                    _num(m.get("demand_kw") or m.get("registered_demand_peak_kw"))
                    for m in measures
                ]
            ),
        )

    recent_periods = sorted(monthly)[-6:]
    monthly_history = [
        {"period": p, **{k: round(v, 2) for k, v in monthly[p].items()}}
        for p in recent_periods
    ]

    relevant_detail: dict[str, Any] = {}

    if intent == "power_factor":
        relevant_detail["low_power_factor"] = low_pf[:40]
    elif intent == "power":
        relevant_detail["power_excess"] = excess[:40]
    elif intent == "consumption":
        relevant_detail["top_consumption"] = top_consumption[:40]
        relevant_detail["monthly_history"] = monthly_history
    elif intent == "cost":
        relevant_detail["top_amount"] = top_amount[:40]
        relevant_detail["monthly_history"] = monthly_history
    elif intent == "missing":
        relevant_detail["missing"] = missing[:100]
    elif intent == "priority":
        relevant_detail["opportunities"] = opportunities[:60]
        relevant_detail["power_excess"] = excess[:20]
        relevant_detail["low_power_factor"] = low_pf[:20]
        relevant_detail["missing"] = missing[:30]
    elif intent == "inactive_supply":
        meter_rows = (
            db.table("meters")
            .select("id,meter_number,supply_number,service_name,status,expected_monthly,last_seen_period,first_seen_period,notes")
            .eq("organization_id", organization_id)
            .execute()
            .data
        )
        relevant_detail["meters_lifecycle"] = meter_rows
        relevant_detail["missing"] = missing[:100]
        relevant_detail["meter_history_6m"] = _meter_history_context(
            db, organization_id, recent_periods
        )
    elif intent == "anomaly":
        trends = _meter_history_context(db, organization_id, recent_periods)
        trends.sort(
            key=lambda x: max(
                abs(_num(x.get("kwh_change_percent"))),
                abs(_num(x.get("amount_change_percent"))),
            ),
            reverse=True,
        )
        relevant_detail["meter_trends_6m"] = trends[:80]
        relevant_detail["monthly_history"] = monthly_history
    elif intent == "tariff":
        relevant_detail["current_tariffs"] = [
            {
                "meter_id": row["meter_id"],
                "meter_number": row["meter_number"],
                "supply_number": row["supply_number"],
                "service_name": row["service_name"],
                "tariff": row["tariff"],
                "voltage_level": row["voltage_level"],
                "contracted_kw": row["contracted_kw"],
                "demand_kw": row["demand_kw"],
                "kwh": row["kwh"],
            }
            for row in enriched
        ]
        relevant_detail["tariff_related_opportunities"] = [
            x for x in opportunities if "tarif" in str(x.get("title") or "").lower()
        ][:60]
    else:
        relevant_detail["top_power_excess"] = excess[:12]
        relevant_detail["top_low_power_factor"] = low_pf[:12]
        relevant_detail["top_consumption"] = top_consumption[:12]
        relevant_detail["top_amount"] = top_amount[:12]
        relevant_detail["missing"] = missing[:20]
        relevant_detail["opportunities"] = opportunities[:20]
        relevant_detail["monthly_history"] = monthly_history

    return {
        "today": date.today().isoformat(),
        "intent": intent,
        "latest_period": latest,
        "summary": {
            "invoices_latest_period": len(enriched),
            "low_power_factor_count": len(low_pf),
            "power_excess_count": len(excess),
            "open_missing_alerts": len(missing),
            "active_opportunities": len(opportunities),
            "annual_saving_total": round(
                sum(_num(x.get("estimated_annual_saving")) for x in opportunities), 2
            ),
            "latest_total_amount": round(
                sum(x["total_amount"] for x in enriched), 2
            ),
            "latest_total_kwh": round(sum(x["kwh"] for x in enriched), 2),
        },
        "relevant_detail": relevant_detail,
    }


def _extract_output_text(payload: dict[str, Any]) -> str:
    if payload.get("output_text"):
        return str(payload["output_text"])
    chunks: list[str] = []
    for item in payload.get("output") or []:
        if item.get("type") != "message":
            continue
        for content in item.get("content") or []:
            if content.get("type") == "output_text" and content.get("text"):
                chunks.append(str(content["text"]))
    return "\n".join(chunks).strip()


@router.post("/ai/query")
def ai_query(body: AIQuery, user: CurrentUser = Depends(current_user)):
    require_org(user.id, body.organization_id)

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(503, "Falta configurar OPENAI_API_KEY en el backend")

    model = os.getenv("OPENAI_MODEL", "gpt-5.4").strip() or "gpt-5.4"
    context = _build_context(body.organization_id, body.question)

    system = """Sos el asistente de gestión energética de una municipalidad argentina.
Tu función es ayudar a tomar decisiones operativas y económicas usando SOLO el CONTEXTO recibido.

REGLAS:
- No inventes datos.
- Priorizá el bloque relevant_detail: fue preparado específicamente para la intención de la pregunta.
- latest_period es el período actual de análisis.
- Para cos φ, menor a 0,95 requiere revisión.
- Para potencia, diferenciá siempre contratada, demanda máxima y sobrante.
- Un suministro sin factura no significa automáticamente que esté dado de baja.
- Un cambio tarifario es candidato a revisión; no afirmes que EPEN lo aprobará sin evidencia.
- Los ahorros son estimaciones.
- Si la información no alcanza, indicá exactamente qué dato falta.

FORMA DE RESPONDER:
1. Empezá con una conclusión directa en 1 o 2 líneas.
2. Si hay varios casos, ordenalos por prioridad económica/operativa.
3. En cada caso escribí el nombre y además **Medidor NÚMERO** o **Suministro NÚMERO** para que la interfaz pueda abrir el análisis individual.
4. Indicá el dato que dispara la recomendación.
5. Indicá la acción concreta sugerida.
6. Cuando sea posible, separá "ahorro sin inversión" de "requiere inversión".
7. Evitá explicaciones genéricas y repetitivas.
8. No uses tablas salvo que el usuario las pida.
9. Para preguntas de prioridad, devolvé como máximo 5 acciones principales.
10. Para anomalías, compará contra meses anteriores y no señales cambios pequeños como críticos.
11. Para posibles bajas, usá historial, última factura, consumo y estado; nunca concluyas baja solo porque falta una factura.
"""

    request_payload = {
        "model": model,
        "instructions": system,
        "input": (
            f"PREGUNTA DEL USUARIO:\n{body.question}\n\n"
            f"INTENCIÓN DETECTADA:\n{context.get('intent')}\n\n"
            f"CONTEXTO DE LA BASE:\n{json.dumps(context, ensure_ascii=False, separators=(',', ':'))}"
        ),
        "store": False,
        "max_output_tokens": 750,
        "text": {"verbosity": "low"},
    }

    try:
        with httpx.Client(timeout=60.0) as client:
            response = client.post(
                "https://api.openai.com/v1/responses",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json=request_payload,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(502, f"No se pudo conectar con OpenAI: {exc}") from exc

    if response.status_code >= 400:
        detail = response.text[:1200]
        raise HTTPException(
            response.status_code, f"OpenAI respondió con error: {detail}"
        )

    payload = response.json()
    answer = _extract_output_text(payload)
    if not answer:
        raise HTTPException(502, "OpenAI no devolvió texto")

    return {
        "answer": answer,
        "model": payload.get("model", model),
        "response_id": payload.get("id"),
        "latest_period": context.get("latest_period"),
        "intent": context.get("intent"),
        "summary": context.get("summary"),
    }
