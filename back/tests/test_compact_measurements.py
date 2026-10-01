from app.routers.invoices import _compact_invoice


def test_missing_demand_remains_missing_for_t2_optimization():
    result = _compact_invoice({'invoice_measurements': [{'active_energy_kwh': 100}], 'invoice_lines': []})
    row = result['invoice_measurements'][0]
    assert row['registered_demand_peak_kw'] is None
    assert row['demand_kw'] is None


def test_real_zero_and_precise_demand_are_preserved_separately():
    result = _compact_invoice({'invoice_measurements': [
        {'registered_demand_peak_kw': 0, 'demand_kw': 0},
        {'registered_demand_peak_kw': 25, 'demand_kw': 25.39},
    ], 'invoice_lines': []})
    row = result['invoice_measurements'][0]
    assert row['registered_demand_peak_kw'] == 25
    assert row['demand_kw'] == 25.39
    zero = _compact_invoice({'invoice_measurements': [{'demand_kw': 0, 'registered_demand_peak_kw': 0}], 'invoice_lines': []})
    assert zero['invoice_measurements'][0]['registered_demand_peak_kw'] == 0
