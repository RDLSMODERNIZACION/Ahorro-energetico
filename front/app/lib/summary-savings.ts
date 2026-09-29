import type { MeterChangeControl } from "../meter-change-control";

type InvoiceKey = {
  id: string; meter_id: string; billing_period?: string; period_start: string;
  issue_date?: string; total_amount: number; document_type?: string;
  invoice_measurements?: unknown[]; invoice_lines?: { concept_code?: string }[];
};
export const billingMonth = (row: InvoiceKey) => String(row.billing_period || row.period_start).slice(0, 7);
export function primaryInvoices<T extends InvoiceKey>(rows: T[]): T[] {
  const selected = new Map<string, T>();
  const score = (row: T) => (row.invoice_measurements?.length ? 2 : 0) +
    (row.invoice_lines?.some(line => ["DEM", "DEP", "COS"].includes(line.concept_code || "")) ? 1 : 0);
  const order = (a: T, b: T) => score(b) - score(a) ||
    String(b.issue_date || "").localeCompare(String(a.issue_date || "")) || b.id.localeCompare(a.id);
  for (const row of [...rows].sort(order)) {
    if (row.document_type === "credit_note" || Number(row.total_amount) < 0) continue;
    const key = `${row.meter_id}:${billingMonth(row)}`;
    if (!selected.has(key)) selected.set(key, row);
  }
  return [...selected.values()].sort((a, b) => billingMonth(b).localeCompare(billingMonth(a)) || a.meter_id.localeCompare(b.meter_id));
}
export const savingKinds = ["contracted_power", "power_factor", "tariff", "supply_deactivation"] as const;
export function confirmedSavings(controls: MeterChangeControl[], period: string) {
  const latest = new Map<string, MeterChangeControl>();
  for (const row of [...controls].sort((a, b) => a.effective_period.localeCompare(b.effective_period) ||
      String(a.created_at || "").localeCompare(String(b.created_at || "")) || a.id.localeCompare(b.id))) {
    if (!["applied", "verified"].includes(row.status) || row.effective_period.slice(0, 7) > period) continue;
    latest.set(`${row.meter_id}:${row.change_type}`, row);
  }
  const rows = [...latest.values()].filter(row => {
    if (row.change_type !== "contracted_power") return true;
    const months = Array.isArray(row.details?.months) ? row.details.months as Record<string, unknown>[] : [];
    if (!months.length) return true;
    return months.some(month => Number(month.monthNumber) === Number(period.slice(5, 7)) &&
      (!month.application_year || Number(month.application_year) === Number(period.slice(0, 4))) && Number(month.effective_kw) > 0);
  });
  // A deactivation replaces the other savings of that same supply.
  const removed = new Set(rows.filter(row => row.change_type === "supply_deactivation").map(row => row.meter_id));
  const applicable = rows.filter(row => !removed.has(row.meter_id) || row.change_type === "supply_deactivation");
  const totals: Record<string, number> = Object.fromEntries(savingKinds.map(kind => [kind, 0]));
  const meterIds: Record<string, string[]> = Object.fromEntries(savingKinds.map(kind => [kind, []]));
  let unvalued = 0;
  for (const row of applicable) {
    const stored = row.change_type === "supply_deactivation" ? row.details?.baseline_monthly_cost : row.details?.projected_monthly_saving;
    if (stored === null || stored === undefined || !Number.isFinite(Number(stored)) || Number(stored) < 0) { unvalued++; continue; }
    totals[row.change_type] += Number(stored);
    if (Number(stored) > 0) meterIds[row.change_type].push(row.meter_id);
  }
  return { totals, meterIds, monthly: Object.values(totals).reduce((sum, value) => sum + value, 0), count: applicable.length, unvalued };
}
