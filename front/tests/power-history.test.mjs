import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../app/lib/power-history.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const { consumptionPeriod, measuredDemand, latestMonthlyDemands } = await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
const invoice = (start, end, billing, demand) => ({period_start: start, period_end: end, billing_period: billing, invoice_measurements: [{demand_kw: demand}]});
test('uses reading month despite a later invoice, including year rollover', () => {
  assert.equal(consumptionPeriod(invoice('2026-01-31', '2026-02-28', '2026-03', 510)), '2026-02');
  assert.equal(consumptionPeriod(invoice('2025-12-01', '2026-01-01', '2026-02', 480)), '2025-12');
  assert.equal(consumptionPeriod(invoice('2026-03-01', '2026-03-31', '2026-03', 312)), '2026-03');
});
test('does not invent a previous month when dates are missing or invalid', () => {
  assert.equal(consumptionPeriod({billing_period: '2026-03'}), '2026-03');
  assert.equal(consumptionPeriod(invoice('2026-03-31', '2026-03-01', '2026-04', 432)), '2026-04');
});
test('takes highest measured demand, never contracted power', () => {
  assert.equal(measuredDemand({contracted_kw_peak: 800, invoice_measurements: [{demand_kw: 312, registered_demand_peak_kw: 432}, {registered_demand_off_peak_kw: 450}]}), 450);
});
test('compares latest two distinct consumption years and deduplicates the month conservatively', () => {
  const history = [invoice('2024-02-29', '2024-03-31', '2024-04', 600), invoice('2025-02-28', '2025-03-31', '2025-04', 432), invoice('2026-02-28', '2026-03-31', '2026-04', 310), invoice('2026-02-28', '2026-03-31', '2026-05', 312), invoice('2026-01-31', '2026-02-28', '2026-03', 510)];
  const march = latestMonthlyDemands(history, 3);
  assert.deepEqual(march.map(x => [x.period, x.demand]), [['2026-03', 312], ['2025-03', 432]]);
  assert.equal(Math.max(...march.map(x => x.demand)), 432);
  assert.equal(latestMonthlyDemands(history, 2)[0].demand, 510);
  assert.deepEqual(latestMonthlyDemands(history, 7), []);
});

test('proposal and shared savings use consumption month; tariff savings retain billing month', () => {
  const panel = readFileSync(new URL('../app/invoice-analysis-panel.tsx', import.meta.url), 'utf8');
  const logic = panel.slice(panel.indexOf('const powerMonthNames'), panel.indexOf('function xmlCell')).replace('export function', 'function');
  const output = ts.transpileModule(logic, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  const { buildPowerCurve, calculateCanonicalSavings } = new Function('latestMonthlyDemands', 'consumptionPeriod', 'periodOf', 'values', 'contractedBands', 'const nf = new Intl.NumberFormat("es-AR");' + output + ';return {buildPowerCurve,calculateCanonicalSavings};')(
    latestMonthlyDemands, consumptionPeriod, i => i.billing_period, i => ({ demand: measuredDemand(i) }), i => ({peak:i.contracted_kw_peak}),
  );
  const amounts = [502,510,432,456,432,446,432,422,429,484,466,480];
  const history = amounts.map((demand, index) => {
    const month = index + 1;
    const start = new Date(Date.UTC(2025, month - 1, 0)).toISOString().slice(0,10);
    const end = new Date(Date.UTC(2025, month, 0)).toISOString().slice(0,10);
    const billed = new Date(Date.UTC(2025, month, 1)).toISOString().slice(0,7);
    return {...invoice(start,end,billed,demand), meter_id:'test',contracted_kw_peak:510,current_tariff_code:'T3',invoice_lines:[{concept_code:'DEP',unit_price:100}]};
  });
  assert.deepEqual(buildPowerCurve(history).rows.map(r => r.proposalKw), amounts);
  const selected = {...history[7], ...invoice('2026-07-31','2026-08-31','2026-09',408)};
  const result = calculateCanonicalSavings({invoice:selected,history:[...history,selected],tariffSavings:[{meter_id:'test',billing_period:'2026-09',monthly_saving_with_vat:1000},{meter_id:'test',billing_period:'2026-08',monthly_saving_with_vat:9999}]});
  assert.equal(result.powerMonthly, (510 - 422) * 100 * 1.3);
  assert.equal(result.tariffMonthly, 1000);
});
