import csv
import hashlib
import io
import re
import zipfile
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from fastapi import HTTPException
from .db import admin_db

ALIASES = {
    "meter": ("medidor", "numero medidor", "suministro", "nis"),
    "site": ("ubicacion", "sitio", "dependencia", "lugar"),
    "period": ("periodo", "fecha", "mes"),
    "kwh": ("kwh", "energia activa", "consumo"),
    "kw": ("demanda", "potencia maxima", "kw max"),
    "contracted": ("potencia contratada", "contratada"),
    "amount": ("importe total", "monto", "total factura", "total"),
    "reactive": ("energia reactiva", "reactiva", "kvarh"),
    "tariff": ("tarifa", "categoria tarifaria"),
    "voltage": ("nivel tension", "tension"),
}

def normalize(value: str) -> str:
    import unicodedata
    return " ".join(unicodedata.normalize("NFD", value.lower()).encode("ascii", "ignore").decode().strip().split())

def decimal(value: str | None) -> Decimal:
    if not value:
        return Decimal("0")
    clean = value.strip().replace("$", "").replace(" ", "")
    if clean.count(",") == 1:
        clean = clean.replace(".", "").replace(",", ".")
    try:
        return Decimal(clean)
    except InvalidOperation:
        return Decimal("0")

def parse_period(value: str) -> tuple[date, date]:
    numbers = [int(x) for x in re.findall(r"\d+", value or "")]
    if len(numbers) >= 2:
        year, month = (numbers[0], numbers[1]) if numbers[0] > 1900 else (numbers[1], numbers[0])
    else:
        now = datetime.utcnow(); year, month = now.year, now.month
    start = date(year, max(1, min(month, 12)), 1)
    end = date(year + (month == 12), 1 if month == 12 else month + 1, 1)
    return start, date.fromordinal(end.toordinal() - 1)

def csv_files(payload: bytes, filename: str) -> list[tuple[str, bytes]]:
    if filename.lower().endswith(".zip"):
        try:
            with zipfile.ZipFile(io.BytesIO(payload)) as archive:
                return [(n, archive.read(n)) for n in archive.namelist() if n.lower().endswith(".csv") and not n.startswith("__MACOSX/")]
        except zipfile.BadZipFile as exc:
            raise HTTPException(400, "El ZIP está dañado") from exc
    if filename.lower().endswith(".csv"):
        return [(filename, payload)]
    raise HTTPException(400, "Solo se admiten archivos ZIP o CSV")

def parse_csv(payload: bytes) -> list[dict]:
    text = payload.decode("utf-8-sig", errors="replace")
    sample = text[:4096]
    delimiter = ";" if sample.count(";") > sample.count(",") else ","
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    headers = {normalize(h): h for h in (reader.fieldnames or [])}
    mapping = {}
    for field, aliases in ALIASES.items():
        mapping[field] = next((original for normalized, original in headers.items() if any(a in normalized for a in aliases)), None)
    result = []
    for raw in reader:
        get = lambda key: raw.get(mapping[key], "") if mapping.get(key) else ""
        if not get("meter"):
            continue
        start, end = parse_period(get("period"))
        result.append({"meter_number": get("meter").strip(), "site": get("site").strip() or "Sin ubicación",
          "period_start": start.isoformat(), "period_end": end.isoformat(), "kwh": decimal(get("kwh")),
          "kw": decimal(get("kw")), "contracted": decimal(get("contracted")), "amount": decimal(get("amount")),
          "reactive": decimal(get("reactive")), "tariff": get("tariff").strip() or None,
          "voltage": get("voltage").strip().upper() or None, "raw": raw})
    return result

def import_invoices(organization_id: str, user_id: str, filename: str, payload: bytes) -> dict:
    db = admin_db(); digest = hashlib.sha256(payload).hexdigest()
    existing = db.table("import_batches").select("id,status").eq("organization_id", organization_id).eq("file_hash", digest).execute()
    if existing.data:
        return {"duplicate": True, "batch": existing.data[0]}
    batch = db.table("import_batches").insert({"organization_id": organization_id, "uploaded_by": user_id,
      "file_name": filename, "file_type": filename.rsplit(".",1)[-1].lower(), "file_hash": digest, "status": "processing"}).execute().data[0]
    imported = rejected = 0; errors = []
    try:
        rows = []
        for _, content in csv_files(payload, filename): rows.extend(parse_csv(content))
        periods = sorted({row["period_start"] for row in rows})
        if len(periods) > 1:
            raise HTTPException(400, "Cada carga debe contener un único período mensual")
        billing_period = periods[0] if periods else None
        imported_meter_ids: set[str] = set()
        for index, row in enumerate(rows, start=2):
            try:
                site_result = db.table("sites").select("id").eq("organization_id",organization_id).eq("name",row["site"]).limit(1).execute()
                site_id = site_result.data[0]["id"] if site_result.data else db.table("sites").insert({"organization_id":organization_id,"name":row["site"]}).execute().data[0]["id"]
                meter_result = db.table("meters").select("id").eq("organization_id",organization_id).eq("provider","EPEN").eq("meter_number",row["meter_number"]).limit(1).execute()
                meter_id = meter_result.data[0]["id"] if meter_result.data else db.table("meters").insert({"organization_id":organization_id,"site_id":site_id,"meter_number":row["meter_number"],"current_tariff_code":row["tariff"],"voltage_level":row["voltage"],"contracted_kw_peak":str(row["contracted"]),"first_seen_period":row["period_start"],"last_seen_period":row["period_start"]}).execute().data[0]["id"]
                db.table("meters").update({"site_id":site_id,"last_seen_period":row["period_start"],"current_tariff_code":row["tariff"],"status":"active","expected_monthly":True,"removed_at":None,"notes":"Reactivado automáticamente al ingresar una factura"}).eq("id",meter_id).execute()
                imported_meter_ids.add(meter_id)
                invoice = db.table("invoices").upsert({"organization_id":organization_id,"meter_id":meter_id,"import_batch_id":batch["id"],"period_start":row["period_start"],"period_end":row["period_end"],"current_tariff_code":row["tariff"],"voltage_level":row["voltage"],"contracted_kw_peak":str(row["contracted"]),"subtotal":str(row["amount"]),"total_amount":str(row["amount"]),"raw_data":row["raw"]},on_conflict="organization_id,provider,meter_id,period_start,period_end").execute().data[0]
                db.table("invoice_measurements").upsert({"invoice_id":invoice["id"],"time_band":"all","active_energy_kwh":str(row["kwh"]),"reactive_energy_kvarh":str(row["reactive"]),"demand_kw":str(row["kw"])},on_conflict="invoice_id,time_band").execute()
                imported += 1
            except Exception as exc:
                rejected += 1; errors.append({"row":index,"error":str(exc)[:300]})
        status = "completed" if not rejected else "partial"
        db.table("import_batches").update({"status":status,"billing_period":billing_period,"total_rows":len(rows),"imported_rows":imported,"rejected_rows":rejected,"errors":errors,"completed_at":datetime.utcnow().isoformat()}).eq("id",batch["id"]).execute()

        missing = []
        if billing_period:
            expected = db.table("meters").select("id,tracking_code,meter_number,sites(name)").eq("organization_id",organization_id).neq("status","removed").eq("expected_monthly",True).execute().data
            for meter in expected:
                if meter["id"] not in imported_meter_ids:
                    site_name = (meter.get("sites") or {}).get("name") or "Sin ubicación"
                    message = f"Falta la factura de {site_name} - {meter['meter_number']} ({meter['tracking_code']}) para {billing_period[:7]}"
                    alert = {"organization_id":organization_id,"meter_id":meter["id"],"expected_period":billing_period,"detected_by_batch_id":batch["id"],"status":"open","message":message}
                    db.table("missing_invoice_alerts").upsert(alert,on_conflict="meter_id,expected_period").execute()
                    missing.append({"tracking_code":meter["tracking_code"],"meter_number":meter["meter_number"],"site":site_name,"message":message})
            if imported_meter_ids:
                db.table("missing_invoice_alerts").update({"status":"resolved","resolved_at":datetime.utcnow().isoformat(),"resolution_note":"Factura incorporada en una carga posterior"}).eq("expected_period",billing_period).in_("meter_id",list(imported_meter_ids)).eq("status","open").execute()
        return {"duplicate":False,"batch_id":batch["id"],"billing_period":billing_period,"total":len(rows),"imported":imported,"rejected":rejected,"missing_count":len(missing),"missing_meters":missing,"errors":errors[:20]}
    except Exception as exc:
        db.table("import_batches").update({"status":"failed","errors":[{"error":str(exc)[:500]}],"completed_at":datetime.utcnow().isoformat()}).eq("id",batch["id"]).execute()
        raise
