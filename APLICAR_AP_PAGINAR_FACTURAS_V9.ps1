$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$file = Join-Path $repo "back\app\routers\public_lighting.py"

if(-not (Test-Path $file)){
    throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $file "$file.bak-$stamp" -Force

$text = Get-Content $file -Raw -Encoding UTF8

$old = @'
    invoices = []
    if linked_ids:
        # EXACTAMENTE la misma fuente de datos que Dependencias.
        invoices = (
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
            .execute()
            .data
            or []
        )
'@

$new = @'
    invoices = []
    if linked_ids:
        # IMPORTANTE:
        # Supabase/PostgREST limita por defecto la respuesta a ~1000 filas.
        # AP tiene más de 1800 facturas históricas, por lo que una consulta única
        # devolvía solamente las más viejas. Eso hacía que 2026-08 no existiera
        # dentro del conjunto cargado y aparecieran 0 facturas recibidas.
        #
        # Paginamos explícitamente hasta traer TODO el histórico de los medidores AP.
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
'@

if(-not $text.Contains($old)){
    throw "No encontré el bloque de consulta de invoices esperado. No hice cambios."
}

$text = $text.Replace($old,$new)
Set-Content $file -Value $text -Encoding UTF8

Write-Host ""
Write-Host "AP PAGINAR FACTURAS V9 aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Causa corregida:" -ForegroundColor Cyan
Write-Host "  Supabase devolvía solo las primeras ~1000 facturas AP."
Write-Host "  Como estaban ordenadas de más vieja a más nueva, 2026-08 quedaba afuera."
Write-Host "  Ahora el backend pagina y trae todo el histórico."
Write-Host ""
Write-Host "Backup: $file.bak-$stamp"
Write-Host ""
Write-Host "IMPORTANTE: reiniciá / desplegá el BACKEND de Render." -ForegroundColor Yellow
