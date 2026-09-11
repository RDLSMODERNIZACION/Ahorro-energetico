/** Keep consumption dates separate from billing dates used for prices and payments. */
export type PowerInvoice = {
  billing_period?: string;
  period_start?: string;
  period_end?: string;
  invoice_measurements?: Array<{
    demand_kw?: number;
    registered_demand_peak_kw?: number;
    registered_demand_off_peak_kw?: number;
  }>;
};

export function consumptionPeriod(invoice: PowerInvoice): string {
  const start = Date.parse(String(invoice.period_start || '').slice(0, 10));
  const end = Date.parse(String(invoice.period_end || '').slice(0, 10));
  // Meter readings delimit (start, end]. Assign the whole measured peak to the
  // month containing most reading days; never split or prorate a peak in kW.
  if (Number.isFinite(start) && Number.isFinite(end) && end > start && end - start <= 93 * 86400000) {
    const days = new Map<string, number>();
    for (let day = start + 86400000; day <= end; day += 86400000) {
      const month = new Date(day).toISOString().slice(0, 7);
      days.set(month, (days.get(month) || 0) + 1);
    }
    return [...days].sort((a, b) => b[1] - a[1] || b[0].localeCompare(a[0]))[0][0];
  }
  return String(invoice.billing_period || invoice.period_end || invoice.period_start || '').slice(0, 7);
}

export function measuredDemand(invoice: PowerInvoice): number {
  return Math.max(0, ...(invoice.invoice_measurements || []).flatMap((m) =>
    [m.demand_kw, m.registered_demand_peak_kw, m.registered_demand_off_peak_kw]
      .map((value) => Number(value)).filter(Number.isFinite),
  ));
}

export function latestMonthlyDemands(history: PowerInvoice[], month: number) {
  const periods = new Map<string, { period: string; demand: number; billingPeriod: string }>();
  for (const invoice of history) {
    const period = consumptionPeriod(invoice);
    const demand = measuredDemand(invoice);
    if (Number(period.slice(5, 7)) !== month || demand <= 0) continue;
    // Multiple invoices/measurements for one consumption month count once.
    const previous = periods.get(period);
    if (!previous || demand > previous.demand) {
      periods.set(period, { period, demand, billingPeriod: String(invoice.billing_period || '').slice(0, 7) });
    }
  }
  return [...periods.values()].sort((a, b) => b.period.localeCompare(a.period)).slice(0, 2);
}
