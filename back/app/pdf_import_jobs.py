"""Background import orchestration. A PDF and its measurements commit atomically."""
import hashlib
import logging
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import PurePosixPath

from fastapi import HTTPException
from .db import admin_db
from .pdf_invoices import documents, parse_pdf

log = logging.getLogger(__name__)


def contract_key(value):
    parts = (value or '').split('/')
    if len(parts) != 2 or not all(x.isdigit() for x in parts):
        return None
    return (int(parts[0]), int(parts[1]))


def choose_meter(data, meters, lighting):
    key = contract_key(data['supply_contract'])
    lights = [m for m in lighting if contract_key(m.get('supply_contract')) == key]
    if len(lights) == 1:
        return None, lights[0]['id']
    if len(lights) > 1:
        raise ValueError('El suministro coincide con varios registros de alumbrado')
    candidates = []
    for meter in meters:
        supply = meter.get('supply_number') or meter.get('service_code') or ''
        seq = meter.get('contract_number') or ''
        full = contract_key(supply) or contract_key(f'{supply}/{seq}')
        if full is None:
            parts = (meter.get('tracking_code') or '').split('-')
            full = contract_key('/'.join(parts[-2:]))
        if full == key:
            candidates.append(meter)
    if len(candidates) != 1:
        raise ValueError('Suministro inexistente o ambiguo. Revisá su alta en Medidores antes de importar.')
    return candidates[0]['id'], None


def duplicate_status(data, existing):
    invoice = data['invoice']
    found = existing.get(invoice['invoice_number'], [])
    if not found:
        return None
    if any(x.get('billing_period') != invoice['billing_period'] or Decimal(str(x['total_amount'])) != Decimal(invoice['total_amount']) for x in found):
        return {'status':'conflict','message':'Ya existe con otro período o importe. No se reemplazó.'}
    return {'status':'duplicate','message':'Factura ya registrada'}


def all_rows(db, table, columns, org):
    result = []
    for start in range(0, 100000, 1000):
        rows = db.table(table).select(columns).eq('organization_id', org).order('id').range(start, start+999).execute().data
        result.extend(rows)
        if len(rows) < 1000:
            return result
    raise ValueError('Demasiados registros para esta importación')


def start_job(org, user, filename, payload):
    # Validate archive limits before accepting a background job.
    files = documents(payload, filename)
    if any(not name.lower().endswith('.pdf') for name, _ in files):
        raise ValueError('Para importar PDF, el ZIP/RAR debe contener solo PDF. Cargá los CSV por separado.')
    db = admin_db()
    digest = hashlib.sha256(payload).hexdigest()
    old = db.table('import_batches').select('*').eq('organization_id', org).eq('file_hash', digest).execute().data
    if old:
        batch = old[0]
        created = datetime.fromisoformat(batch['created_at'].replace('Z', '+00:00'))
        age = (datetime.now(timezone.utc)-created).total_seconds()
        if batch['status'] in ('pending','processing') and age < 900:
            return batch['id'], False
        # Partial/failed batches can be retried; per-invoice checks prevent duplicates.
        batch = db.table('import_batches').update({'status':'pending','result':None,'errors':[], 'created_at':datetime.now(timezone.utc).isoformat(), 'completed_at':None,'imported_rows':0,'rejected_rows':0}).eq('id', batch['id']).eq('status',batch['status']).eq('created_at',batch['created_at']).execute().data
        if not batch:
            return old[0]['id'], False
        batch = batch[0]
    else:
        try:
            batch = db.table('import_batches').insert({'organization_id':org,'uploaded_by':user,'file_name':filename,'file_type':PurePosixPath(filename).suffix.lstrip('.'),'file_hash':digest,'status':'pending','total_rows':len(files)}).execute().data[0]
        except Exception:
            raced = db.table('import_batches').select('id').eq('organization_id',org).eq('file_hash',digest).execute().data
            if raced:
                return raced[0]['id'],False
            raise
    return batch['id'], True


def run_job(batch_id, org, filename, payload):
    db = admin_db()
    result = {'imported':0,'updated':0,'duplicates':0,'rejected':0,'total':0,'processed':0,'details':[]}
    try:
        db.table('import_batches').update({'status':'processing'}).eq('id',batch_id).execute()
        files = documents(payload, filename)
        result['total'] = len(files)
        meters = all_rows(db,'meters','id,tracking_code,supply_number,contract_number,service_code,meter_number',org)
        lighting = all_rows(db,'public_lighting_meters','id,supply_contract,meter_number',org)
        existing = {}
        for table in ('invoices','public_lighting_invoices'):
            for item in all_rows(db,table,'id,invoice_number,billing_period,total_amount',org):
                existing.setdefault(item['invoice_number'],[]).append(item)
        for name, content in files:
            detail = {'file':name}
            try:
                data = parse_pdf(content,name)
                detail.update(invoice_number=data['invoice']['invoice_number'],period=data['invoice']['billing_period'])
                status = duplicate_status(data,existing)
                if status is None or status['status'] == 'duplicate':
                    meter_id, light_id = choose_meter(data,meters,lighting)
                    path = f"{org}/invoices/{data['invoice']['document_hash']}.pdf"
                    db.storage.from_('energy-documents').upload(path,content,{'content-type':'application/pdf','upsert':'true'})
                    data['invoice']['document_path'] = path
                    status = db.rpc('import_epen_pdf',{'p_org':org,'p_batch':batch_id,'p_meter':meter_id,'p_lighting':light_id,'p_data':data}).execute().data
                    if status.get('status') == 'imported':
                        existing.setdefault(data['invoice']['invoice_number'],[]).append(data['invoice'])
                detail.update(status)
            except ValueError as exc:
                detail.update(status='rejected',message=str(exc))
            except Exception:
                log.exception('Invoice import failed: batch=%s file=%s',batch_id,name)
                detail.update(status='rejected',message='No se pudo guardar esta factura. Podés reintentar la carga; las registradas se revisan sin duplicarlas.')
            field = 'imported' if detail['status']=='imported' else 'updated' if detail['status']=='updated' else 'duplicates' if detail['status']=='duplicate' else 'rejected'
            result[field] += 1
            result['processed'] += 1
            result['details'].append(detail)
            db.table('import_batches').update({'result':result,'imported_rows':result['imported'],'rejected_rows':result['rejected']}).eq('id',batch_id).execute()
        state = 'completed' if not result['rejected'] else 'partial' if result['imported'] or result['updated'] or result['duplicates'] else 'failed'
        db.table('import_batches').update({'status':state,'result':result,'total_rows':result['total'],'completed_at':datetime.now(timezone.utc).isoformat(),'errors':[x for x in result['details'] if x['status'] in ('conflict','rejected')]}).eq('id',batch_id).execute()
        if result['imported'] or result['updated']:
            from .energy_intelligence import refresh_energy_intelligence
            try:
                refresh_energy_intelligence(org)
            except Exception:
                log.exception('Energy refresh failed after batch %s',batch_id)
    except Exception:
        log.exception('Import batch failed: %s',batch_id)
        result['error'] = 'La carga se interrumpió. Volvé a subir el archivo; las facturas ya guardadas no se duplican.'
        db.table('import_batches').update({'status':'failed','result':result,'completed_at':datetime.now(timezone.utc).isoformat()}).eq('id',batch_id).execute()
