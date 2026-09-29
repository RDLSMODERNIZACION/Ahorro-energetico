import io
import zipfile
from decimal import Decimal
import pytest
from pypdf import PdfWriter
from app.pdf_invoices import amount, documents, parse_text, parse_pdf
from app.pdf_import_jobs import choose_meter, duplicate_status

TEXT = '''SUMINISTRO / CONTRATO Nº: 00048765/01
FACTURA Nº 0000-12345678
Período Facturación: 09/2026
Lugar y Fecha Emisión: 08/09/2026
Vencimiento: 21/09/2026
Período de Lecturas desde el día 31/07/2026 al dia 31/08/2026
2223190  100,00  110,00  1  10  kWh
-Contratada Única o en Pico: 0 kW
-Registrada Única o en Pico: 0 kW
-Registrada Período Actual: 10 kWh
Registrada: 0 kVArh- Tangente de Fi= 0.00 - Recargo 0.0 %
Tarifa: T1G-GENERAL Tensión: 1-Baja Tensión
CONCEPTOS GRAVADOS
 CFI  Cargo Fijo             1   100,00000   100,00  OIM Ord. Imp. Munic.CM 9,00
 ECO  Energia Consumida     10     1,00000    10,00
Total Impuestos Municipales $ 9,00
Neto de Conceptos Gravados sujeto a IVA e Impuestos: $ 110,00
Impuesto al Valor Agregado – IVA $ 29,70
Percepción IVA %3 $ 3,30
TOTAL FACTURADO $ 152,00
TOTAL A PAGAR $ 152,00
'''


def test_pdf_fields_preserve_billing_and_consumption_periods():
    d = parse_text(TEXT, 'invoice.pdf')
    assert d['invoice']['billing_period'] == '2026-09-01'
    assert d['invoice']['period_start'] == '2026-07-31'
    assert d['invoice']['municipal_tax_amount'] == '9.00'
    assert d['invoice']['total_amount'] == '152.00'
    assert len(d['lines']) == 2
    assert d['measurements'][0]['active_energy_kwh'] == '10'

@pytest.mark.parametrize('source,expected',[('1.234,56','1234.56'),('967.9','967.9'),('191.040','191040'),('0,00','0.00')])
def test_numeric_formats(source,expected):
    assert amount(source) == Decimal(expected)


def test_conflicting_existing_invoice_is_not_overwritten():
    d = parse_text(TEXT,'invoice.pdf')
    old = {d['invoice']['invoice_number']:[{'billing_period':'2026-09-01','total_amount':'99.00'}]}
    assert duplicate_status(d,old)['status'] == 'conflict'
    old[d['invoice']['invoice_number']][0]['total_amount']='152.00'
    assert duplicate_status(d,old)['status'] == 'duplicate'


def test_supply_match_uses_contract_not_changed_physical_meter():
    d=parse_text(TEXT,'invoice.pdf')
    meters=[{'id':'m1','supply_number':'48765','contract_number':'01','meter_number':'OLD'}]
    assert choose_meter(d,meters,[]) == ('m1',None)
    assert choose_meter(d,meters,[{'id':'ap1','supply_contract':'48765/01'}]) == (None,'ap1')
    with pytest.raises(ValueError):choose_meter(d,[],[])
    with pytest.raises(ValueError):choose_meter(d,meters*2,[])

@pytest.mark.parametrize('text',[TEXT.replace('110,00\nImpuesto','999,00\nImpuesto'),TEXT.replace('09/2026\nLugar','13/2026\nLugar'),TEXT+'\nFACTURA Nº 0000-99999999'])
def test_invalid_invoice_is_rejected(text):
    with pytest.raises(ValueError):parse_text(text,'bad.pdf')


def test_scan_does_not_silently_import_zero_values():
    stream=io.BytesIO();w=PdfWriter();w.add_blank_page(width=100,height=100);w.write(stream)
    with pytest.raises(ValueError):parse_pdf(stream.getvalue(),'scan.pdf')


def test_archive_is_read_without_extracting_paths():
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,'w') as z:z.writestr('../../invoice.pdf',b'%PDF-placeholder')
    assert documents(stream.getvalue(),'batch.zip')[0][1] == b'%PDF-placeholder'


def test_empty_nested_and_overlarge_archives_are_rejected():
    for entries in ({},{'nested.zip':b'zip'},{str(i)+'.pdf':b'x' for i in range(201)}):
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as z:
            for name,body in entries.items():z.writestr(name,body)
        with pytest.raises(ValueError):documents(stream.getvalue(),'batch.zip')
