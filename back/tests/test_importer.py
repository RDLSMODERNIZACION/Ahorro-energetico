from app.importer import decimal, parse_csv

def test_decimal_argentino():
    assert str(decimal("1.234.567,89")) == "1234567.89"

def test_parse_csv():
    data = "medidor;ubicacion;periodo;kwh;demanda;potencia contratada;importe total\n71470/01;Oeste 1;2026-07;12000;210;480;4500000\n"
    rows = parse_csv(data.encode())
    assert len(rows) == 1
    assert rows[0]["meter_number"] == "71470/01"
    assert str(rows[0]["kwh"]) == "12000"
