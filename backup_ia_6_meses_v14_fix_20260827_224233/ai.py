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


def _latest_invoice_rows(db, organization_id: str) -> tuple[str, list[dict[str, Any]]]:
    rows = (
        db.table("invoices")
        .select(
            "id,meter_id,billing_period,period_start,total_amount,current_tariff_code,"
            "contracted_kw_peak,meters(id,meter_number,tracking_code,supply_number,service_name,"
            "contracted_kw_peak,current_tariff_code,voltage_level),"
            "invoice_measurements(active_energy_kwh,demand_kw,registered_demand_peak_kw,power_factor,"
            "reactive_surcharge_percent)"
        )
        .eq("organization_id", organization_id)
        .order("billing_period", desc=True)
        .limit(1500)
        .execute()
        .data
    )
    periods = sorted({_period(row.get("billing_period") or row.get("period_start")) for row in rows if _period(row.get("billing_period") or row.get("period_start"))})
    latest = periods[-1] if periods else ""
    return latest, [row for row in rows if _period(row.get("billing_period") or row.get("period_start")) == latest]


def _build_context(organization_id: str, question: str) -> dict[str, Any]:
    db = admin_db()
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
        .select("meter_id,expected_period,message,status,meters(meter_number,tracking_code,supply_number,service_name)")
        .eq("organization_id", organization_id)
        .eq("status", "open")
        .order("expected_period", desc=True)
        .limit(200)
        .execute()
        .data
    )

    opportunities = (
        db.table("opportunities")
        .select("meter_id,title,priority,estimated_annual_saving,estimated_investment,status,meters(meter_number,service_name)")
        .eq("organization_id", organization_id)
        .neq("status", "dismissed")
        .order("estimated_annual_saving", desc=True)
        .limit(100)
        .execute()
        .data
    )

    # 24-month compact monthly totals. We intentionally send aggregates, not arbitrary raw SQL access.
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
        bucket = monthly.setdefault(p, {"amount": 0.0, "kwh": 0.0, "max_demand_kw": 0.0})
        bucket["amount"] += _num(inv.get("total_amount"))
        measures = inv.get("invoice_measurements") or []
        bucket["kwh"] += sum(_num(m.get("active_energy_kwh")) for m in measures)
        bucket["max_demand_kw"] = max(
            bucket["max_demand_kw"],
            max([0.0] + [_num(m.get("demand_kw") or m.get("registered_demand_peak_kw")) for m in measures]),
        )
    monthly_history = [
        {"period": p, **{k: round(v, 2) for k, v in monthly[p].items()}}
        for p in sorted(monthly)[-6:]
    ]

    q = question.lower()
    # Include larger relevant slice only when the question asks for it.
    relevant_detail: dict[str, Any] = {}
    if "factor" in q or "cos" in q or "reactiv" in q:
        relevant_detail["low_power_factor"] = low_pf[:60]
    if "potencia" in q or "contrat" in q or "demanda" in q:
        relevant_detail["power_excess"] = excess[:60]
    if "consumo" in q or "energ" in q:
        relevant_detail["top_consumption"] = top_consumption[:60]
    if "importe" in q or "gasto" in q or "costo" in q or "factur" in q:
        relevant_detail["top_amount"] = top_amount[:60]
    if "falt" in q or "pend" in q:
        relevant_detail["missing"] = missing[:100]
    if "ahorro" in q or "oportun" in q or "prior" in q:
        relevant_detail["opportunities"] = opportunities[:100]

    return {
        "today": date.today().isoformat(),
        "latest_period": latest,
        "summary": {
            "invoices_latest_period": len(enriched),
            "low_power_factor_count": len(low_pf),
            "power_excess_count": len(excess),
            "open_missing_alerts": len(missing),
            "active_opportunities": len(opportunities),
            "annual_saving_total": round(sum(_num(x.get("estimated_annual_saving")) for x in opportunities), 2),
            "latest_total_amount": round(sum(x["total_amount"] for x in enriched), 2),
            "latest_total_kwh": round(sum(x["kwh"] for x in enriched), 2),
        },
        "top_low_power_factor": low_pf[:12],
        "top_power_excess": excess[:12],
        "top_consumption": top_consumption[:12],
        "top_amount": top_amount[:12],
        "missing": missing[:25],
        "opportunities": opportunities[:25],
        "monthly_history": monthly_history,
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
Respondé en español claro y profesional. Analizá SOLO los datos que recibís en CONTEXTO.
No inventes medidores, facturas, importes ni conclusiones que no estén respaldadas.
Cuando haya rankings, indicá medidor/servicio y valor.
Para cos φ, considerá que menor a 0,95 requiere revisión.
Para potencia, diferenciá demanda máxima, potencia contratada y sobrante.
Los ahorros son estimaciones; aclará eso cuando corresponda.
Si la información no alcanza para responder algo, decilo explícitamente. Para tendencias y evolución, priorizá los últimos 6 meses de monthly_history y detectá subas, bajas, anomalías y mejoras.
Priorizá respuestas accionables y breves, pero incluí números concretos."""

    request_payload = {
        "model": model,
        "instructions": system,
        "input": (
            f"PREGUNTA DEL USUARIO:\n{body.question}\n\n"
            f"CONTEXTO DE LA BASE:\n{json.dumps(context, ensure_ascii=False, separators=(',', ':'))}"
        ),
        "store": False,
        "text": {"verbosity": "medium"},
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
        raise HTTPException(response.status_code, f"OpenAI respondió con error: {detail}")

    payload = response.json()
    answer = _extract_output_text(payload)
    if not answer:
        raise HTTPException(502, "OpenAI no devolvió texto")

    return {
        "answer": answer,
        "model": payload.get("model", model),
        "response_id": payload.get("id"),
        "latest_period": context.get("latest_period"),
        "summary": context.get("summary"),
    }

