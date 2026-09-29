"""Strict, deterministic reader for digitally generated EPEN invoices."""
import hashlib
import io
import math
import re
import zipfile
from datetime import datetime
from decimal import Decimal
from pathlib import PurePosixPath

from pypdf import PdfReader

MAX_FILES = 200
MAX_EXPANDED = 100 * 1024 * 1024
MAX_DOCUMENT = 10 * 1024 * 1024
NUMBER = r'-?\d[\d.,]*'


def amount(value):
    value = value.strip()
    if not re.fullmatch(NUMBER, value):
        raise ValueError('Importe o lectura inválidos')
    if ',' in value:
        return Decimal(value.replace('.', '').replace(',', '.'))
    if re.fullmatch(r'-?\d{1,3}(?:\.\d{3})+', value):
        return Decimal(value.replace('.', ''))
    return Decimal(value)


def documents(payload, filename):
    """Read bounded archives in memory; never extract archive paths to disk."""
    suffix = PurePosixPath(filename.lower()).suffix
    if suffix in ('.pdf', '.csv'):
        if len(payload) > MAX_DOCUMENT:
            raise ValueError('El documento supera 10 MB')
        return [(filename, payload)]
    result, expanded = [], 0

    def add(name, chunks):
        nonlocal expanded
        if len(result) >= MAX_FILES:
            raise ValueError('Máximo 200 documentos por carga')
        data = bytearray()
        for block in chunks:
            expanded += len(block)
            data.extend(block)
            if expanded > MAX_EXPANDED or len(data) > MAX_DOCUMENT:
                raise ValueError('El archivo expandido supera el límite permitido')
        result.append((name, bytes(data)))

    if suffix == '.zip':
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            if len(archive.infolist()) > 1000:
                raise ValueError('El ZIP contiene demasiadas entradas')
            if sum(x.file_size for x in archive.infolist()) > MAX_EXPANDED:
                raise ValueError('El ZIP expandido supera 100 MB')
            for entry in archive.infolist():
                if entry.is_dir() or '__MACOSX/' in entry.filename:
                    continue
                if PurePosixPath(entry.filename.lower()).suffix not in ('.pdf', '.csv'):
                    raise ValueError('El ZIP debe contener únicamente PDF o CSV (sin carpetas comprimidas anidadas)')
                with archive.open(entry) as stream:
                    add(entry.filename, iter(lambda: stream.read(65536), b''))
    elif suffix == '.rar':
        try:
            import libarchive
        except (ImportError, OSError) as exc:
            raise ValueError('RAR no disponible en este servidor. Convertí el archivo a ZIP.') from exc
        with libarchive.memory_reader(payload) as archive:
            for index, entry in enumerate(archive):
                if index >= 1000:
                    raise ValueError('El RAR contiene demasiadas entradas')
                if entry.isdir:
                    continue
                if not entry.isfile or PurePosixPath(entry.pathname.lower()).suffix not in ('.pdf', '.csv'):
                    raise ValueError('El RAR debe contener únicamente archivos PDF o CSV')
                add(entry.pathname, entry.get_blocks())
    else:
        raise ValueError('Se admiten PDF, ZIP, RAR o CSV')
    if not result:
        raise ValueError('El archivo no contiene facturas PDF ni CSV')
    return result


def parse_pdf(payload, filename):
    if len(payload) > MAX_DOCUMENT:
        raise ValueError('El PDF supera 10 MB')
    reader = PdfReader(io.BytesIO(payload))
    if reader.is_encrypted:
        raise ValueError('PDF protegido con contraseña')
    if not 1 <= len(reader.pages) <= 20:
        raise ValueError('El PDF debe tener entre 1 y 20 páginas')
    text = '\n'.join((p.extract_text(extraction_mode='layout') or '') if p.get('/Contents') else '' for p in reader.pages).replace('\xa0', ' ')
    return parse_text(text, filename, hashlib.sha256(payload).hexdigest())


def parse_text(text, filename, digest=''):
    def get(pattern, label, optional=False):
        match = re.search(pattern, text, re.I)
        if not match:
            if optional:
                return None
            raise ValueError(f'No se pudo leer {label}. Usá el PDF original de EPEN; los escaneos requieren revisión.')
        return match.group(1)

    def money(pattern, label, optional=False):
        value = get(pattern + r'\s*\$?\s*(' + NUMBER + ')', label, optional)
        return str(amount(value)) if value is not None else None

    def day(pattern, label):
        return datetime.strptime(get(pattern + r'\s*(\d{2}/\d{2}/\d{4})', label), '%d/%m/%Y').date().isoformat()

    numbers = set(re.findall(r'FACTURA\s+N[º°o]\s*(\d{4}-\d+)', text, re.I))
    if len(numbers) != 1:
        raise ValueError('Cada PDF debe contener una sola factura EPEN identificable')
    invoice_number = numbers.pop()
    contract = get(r'SUMINISTRO\s*/\s*CONTRATO\s+N[º°o]:\s*(\d+/\d+)', 'suministro/contrato')
    period = get(r'Período Facturación:\s*(\d{2}/\d{4})', 'período de facturación')
    billing = datetime.strptime(period, '%m/%Y').date().isoformat()
    start = day(r'Lecturas desde el día', 'inicio de lecturas')
    end = day(r'Lecturas desde el día\s*\d{2}/\d{2}/\d{4}\s*al d[ií]a', 'fin de lecturas')
    if end < start:
        raise ValueError('Fechas de lectura inconsistentes')
    total = money('TOTAL FACTURADO', 'total facturado')
    subtotal = money('Neto de Conceptos Gravados sujeto a IVA e Impuestos:', 'neto gravado')
    vat = money(r'Impuesto al Valor Agregado\s*[–-]\s*IVA', 'IVA')
    perception = money(r'Percepción IVA\s*%\s*\d+', 'percepción IVA', True)
    municipal = money(r'(?:Total Impuestos Municipales|Tasa Municipal|Tasa Alumbrado Público)', 'tasa municipal', True)
    # Other taxes may exist: use only printed total/net, never infer tax rates.
    if Decimal(total) < Decimal(subtotal) or Decimal(total) < 0:
        raise ValueError('Totales inconsistentes; requiere revisión')
    kwh = money(r'Registrada Período Actual:', 'energía activa')
    reactive = money(r'Registrada:', 'energía reactiva')
    contracted = money(r'Contratada Única o en Pico:', 'potencia contratada')
    demand = money(r'Registrada Única o en Pico:', 'demanda registrada')
    tangent = get(r'Tangente de Fi=\s*(' + NUMBER + ')', 'tangente phi')
    # EPEN prints the tangent and surcharge with a decimal point, unlike amounts.
    tangent = Decimal(tangent.replace(',', '.'))
    surcharge = get(r'Recargo\s*(' + NUMBER + r')\s*%', 'recargo reactiva')
    tariff = get(r'Tarifa:\s*([A-Z0-9]+)', 'tarifa')
    meter_rows = re.findall(r'^\s*(\d+)\s+(' + NUMBER + r')\s+(' + NUMBER + r')\s+(' + NUMBER + r')\s+(' + NUMBER + r')\s+(kWh|kVArh|kW)\b', text, re.M | re.I)
    if not meter_rows:
        raise ValueError('No se pudieron leer los registros del medidor')
    meters = {x[0] for x in meter_rows}
    if len(meters) != 1:
        raise ValueError('Factura con varios medidores: requiere revisión manual')
    lines = []
    concept_section = text.split('CONCEPTOS GRAVADOS', 1)[-1].split('Neto de Conceptos', 1)[0]
    for line in concept_section.splitlines():
        line = re.split(r'\s+(?:OIM\s|Total Impuestos Municipales)', line)[0]
        match = re.match(r'^\s*([A-Z]{2,5})\s+(.+?)\s{2,}(.+?)\s*$', line)
        if not match:
            continue
        code, description, tail = match.groups()
        tokens = tail.split()
        if not tokens or not re.fullmatch(NUMBER, tokens[-1]):
            continue
        net = str(amount(tokens[-1]))
        quantity = price = None
        if len(tokens) == 3 and all(re.fullmatch(NUMBER, t) for t in tokens):
            quantity, price = str(amount(tokens[0])), str(amount(tokens[1]))
        else:
            description += ' ' + ' '.join(tokens[:-1])
        lines.append(dict(concept_code=code, description=description.strip(), quantity=quantity, unit_price=price, net_amount=net, line_number=len(lines)+1, is_penalty=code in ('COS', 'EXC')))
    if not lines or abs(sum(Decimal(x['net_amount']) for x in lines) - Decimal(subtotal)) > Decimal('0.05'):
        raise ValueError('Los conceptos no coinciden con el subtotal. Requiere revisión manual.')
    measured_kwh = sum(amount(x[4]) for x in meter_rows if x[5].lower() == 'kwh')
    if abs(measured_kwh - Decimal(kwh)) > Decimal('1'):
        raise ValueError('Las lecturas no coinciden con la energía activa informada')
    measurement = dict(time_band='all', register_sequence=1, measurement_type='summary', meter_number=next(iter(meters)), active_energy_kwh=kwh, reactive_energy_kvarh=reactive, demand_kw=demand, registered_demand_peak_kw=demand, tangent_phi=str(tangent), power_factor=str(1/math.sqrt(1+float(tangent)**2)), reactive_surcharge_percent=str(Decimal(surcharge.replace(',', '.'))), reading_start=start, reading_end=end)
    if len(meter_rows) == 1:
        measurement.update(reading_previous=str(amount(meter_rows[0][1])), reading_current=str(amount(meter_rows[0][2])), multiplier=str(amount(meter_rows[0][3])))
    inv = dict(invoice_number=invoice_number, provider='EPEN', billing_period=billing, period_start=start, period_end=end, issue_date=day('Lugar y Fecha Emisión:', 'fecha de emisión'), due_date=day('Vencimiento:', 'vencimiento'), current_tariff_code=tariff, voltage_level='MT' if re.search(r'Tensión:\s*2-Media', text) else 'BT', contracted_kw_peak=contracted, subtotal=subtotal, net_taxable=subtotal, vat_amount=vat, vat_perception_amount=perception, municipal_tax_amount=municipal, taxes=str(Decimal(total)-Decimal(subtotal)), total_amount=total, amount_due=money('TOTAL A PAGAR', 'total a pagar'), service_code=contract.split('/')[0], contract_number=contract.split('/')[1], document_hash=digest, raw_text=text, validation_status='valid', raw_data={'source':'epen_pdf_import_v1','filename':filename,'supply_contract':contract,'registers':[list(x) for x in meter_rows]})
    return dict(invoice=inv, measurements=[measurement], lines=lines, supply_contract=contract, meter_number=measurement['meter_number'])
