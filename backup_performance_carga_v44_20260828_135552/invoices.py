from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import CurrentUser, current_user, require_org
from ..db import admin_db


router = APIRouter(tags=["Facturas"])


# No usar "*" en el listado. La tabla invoices contiene raw_text con el texto
# completo de cada PDF. Traerlo para miles de facturas agotaba los 512 MB de
# Render aunque el front solamente necesitara los datos resumidos.
INVOICE_LIST_SELECT = (
    "id,organization_id,meter_id,import_batch_id,invoice_number,provider,"
    "period_start,period_end,issue_date,due_date,current_tariff_code,"
    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,subtotal,taxes,"
    "total_amount,amount_due,currency,billing_period,liquidation_number,"
    "liquidation_class,tariff_name,tariff_class,billing_type,vat_amount,"
    "previous_debt_amount,raw_data,"
    "meters(id,meter_number,nis,tracking_code,supply_number,contract_number,"
    "service_code,service_name,cadastral_number,current_tariff_code,"
    "voltage_level,contracted_kw_peak,contracted_kw_off_peak,sites(name,address)),"
    "invoice_measurements(id,invoice_id,time_band,active_energy_kwh,"
    "reactive_energy_kvarh,demand_kw,power_factor,registered_demand_peak_kw,"
    "registered_demand_off_peak_kw,tangent_phi,reactive_surcharge_percent,"
    "prior_year_energy_kwh,meter_number,measurement_type,unit),"
    "invoice_lines(id,invoice_id,line_number,concept_code,description,quantity,"
    "unit_price,net_amount,total_amount,is_penalty,is_bonus)"
)


@router.get("/organizations/{organization_id}/invoices")
def invoices(
    organization_id: str,
    meter_id: str | None = None,
    limit: int = Query(100, ge=1, le=5000),
    user: CurrentUser = Depends(current_user),
):
    require_org(user.id, organization_id)

    # PostgREST limita el tamaño de cada respuesta. Se pagina en bloques chicos
    # y se devuelve un único listado compacto, suficiente para tabla y gráficos.
    rows = []
    page_size = 200
    db = admin_db()
    while len(rows) < limit:
        size = min(page_size, limit - len(rows))
        query = (
            db.table("invoices")
            .select(INVOICE_LIST_SELECT)
            .eq("organization_id", organization_id)
        )
        if meter_id:
            query = query.eq("meter_id", meter_id)
        page = (
            query.order("period_start", desc=True)
            .order("id", desc=True)
            .range(len(rows), len(rows) + size - 1)
            .execute()
            .data
        )
        rows.extend(page)
        if len(page) < size:
            break
    return rows


@router.get("/invoices/{invoice_id}")
def invoice(invoice_id: str, user: CurrentUser = Depends(current_user)):
    # El contenido completo se consulta solamente al abrir una factura.
    data = (
        admin_db()
        .table("invoices")
        .select("*,meters(*,sites(*)),invoice_measurements(*),invoice_lines(*)")
        .eq("id", invoice_id)
        .limit(1)
        .execute()
        .data
    )
    if not data:
        raise HTTPException(404, "Factura inexistente")
    require_org(user.id, data[0]["organization_id"])
    return data[0]


@router.delete("/invoices/{invoice_id}", status_code=204)
def delete_invoice(invoice_id: str, user: CurrentUser = Depends(current_user)):
    data = (
        admin_db()
        .table("invoices")
        .select("organization_id")
        .eq("id", invoice_id)
        .limit(1)
        .execute()
        .data
    )
    if not data:
        raise HTTPException(404, "Factura inexistente")
    require_org(user.id, data[0]["organization_id"], write=True)
    admin_db().table("invoices").delete().eq("id", invoice_id).execute()
