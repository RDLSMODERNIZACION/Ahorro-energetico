import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let s = readFileSync(path, "utf8");
if (s.includes("// T2_OPTIMAL_V4")) process.exit(0);

const a = s.indexOf('  if (tariffCode.startsWith("T2")) {');
const b = s.indexOf('\n  const quarterlyDecision = new Map<', a);
if (a < 0 || b < 0) throw new Error("T2 optimizer block not found");

const block = `  if (tariffCode.startsWith("T2")) {
    // T2_OPTIMAL_V4
    const allT2 = [...history]
      .filter((i) => String(i.current_tariff_code || i.meters?.current_tariff_code || "").toUpperCase().startsWith("T2") && powerRate(i) > 0)
      .sort((x, y) => periodOf(x).localeCompare(periodOf(y)))
      .slice(-24);
    const lineRate = (i: Invoice, c: string) => Math.max(0, ...(i.invoice_lines || []).filter((l) => String(l.concept_code || "").toUpperCase() === c).map((l) => Number(l.unit_price || 0)));
    const lineAmount = (i: Invoice, c: string) => (i.invoice_lines || []).filter((l) => String(l.concept_code || "").toUpperCase() === c).reduce((z, l) => z + Math.max(0, Number(l.net_amount || 0) || Number(l.quantity || 0) * Number(l.unit_price || 0)), 0);
    const sim = (i: Invoice, kw: number) => {
      const dem = lineRate(i, "DEM") || powerRate(i) || rate;
      const exc = lineRate(i, "EXC") || dem * 1.5;
      const over = Math.max(0, Math.round(Math.max(0, values(i).demand) - kw));
      return kw * dem + over * exc;
    };
    const actual = (i: Invoice) => lineAmount(i, "DEM") + lineAmount(i, "EXC") || sim(i, contractedBands(i).peak || currentKw);
    const mi = (p: string) => Number(p.slice(0, 4)) * 12 + Number(p.slice(5, 7));
    const newest = allT2.length ? mi(consumptionPeriod(allT2[allT2.length - 1])) : 0;
    const rec3 = allT2.slice(-3), prev9 = allT2.slice(-12, -3);
    const avg = (r: Invoice[]) => r.length ? r.reduce((z, i) => z + Math.max(0, values(i).demand), 0) / r.length : 0;
    const ratio = avg(prev9) > 0 ? avg(rec3) / avg(prev9) : 1;
    const regimeChange = prev9.length >= 3 && (ratio <= 0.65 || ratio >= 1.35);
    const weight = (i: Invoice) => {
      const age = Math.max(0, newest - mi(consumptionPeriod(i)));
      let w = age <= 5 ? 1 : age <= 11 ? 0.75 : 0.4;
      if (regimeChange && age <= 2) w *= 1.5;
      return w;
    };
    const qs = epenPowerQuarters.map((q) => ({
      q,
      hist: allT2.filter((i) => q.months.includes(Number(consumptionPeriod(i).slice(5, 7)))),
    }));
    const penalty = Math.max(0, rate) * 0.1;
    let states = new Map<number, { cost: number; path: number[] }>();
    for (let kw = 10; kw <= 49; kw++) states.set(kw, { cost: qs[0].hist.reduce((z, i) => z + weight(i) * sim(i, kw), 0), path: [kw] });
    for (let qi = 1; qi < qs.length; qi++) {
      const next = new Map<number, { cost: number; path: number[] }>();
      for (let kw = 10; kw <= 49; kw++) {
        let best = { cost: Number.POSITIVE_INFINITY, path: [] as number[] };
        const base = qs[qi].hist.reduce((z, i) => z + weight(i) * sim(i, kw), 0);
        for (const [prev, st] of states) {
          const c = st.cost + base + Math.abs(kw - prev) * penalty;
          if (c < best.cost) best = { cost: c, path: [...st.path, kw] };
        }
        next.set(kw, best);
      }
      states = next;
    }
    let chosen = { cost: Number.POSITIVE_INFINITY, path: [currentKw, currentKw, currentKw, currentKw] };
    for (const st of states.values()) if (st.cost < chosen.cost) chosen = st;
    const qmap = new Map<number, { kw: number; label: string }>();
    qs.forEach((x, idx) => x.q.months.forEach((m) => qmap.set(m, { kw: Number(chosen.path[idx] || currentKw || 10), label: x.q.label })));
    const rows = monthlyRows.map((row) => {
      const d = qmap.get(row.monthNumber)!;
      const monthInvoice = [...allT2].reverse().find((i) => Number(consumptionPeriod(i).slice(5, 7)) === row.monthNumber);
      const demand = monthInvoice ? Math.max(0, values(monthInvoice).demand) : 0;
      const savingNet = monthInvoice ? actual(monthInvoice) - sim(monthInvoice, d.kw) : 0;
      const projectedExcessKw = Math.max(0, Math.round(demand - d.kw));
      return { ...row, monthlyProposalKw: d.kw, proposalKw: d.kw, quarterlyProposalKw: d.kw, quarter: d.label, method: "trimestral" as const, reason: "T2 óptimo trimestral ponderado por recencia" + (regimeChange ? " · cambio reciente de patrón detectado" : "") + (projectedExcessKw ? " · EXC proyectado " + nf.format(projectedExcessKw) + " kW" : ""), spreadKw: 0, extraCost: 0, reducibleKw: Math.max(0, currentKw - d.kw), savingNet, saving: savingNet * 1.3, projectedExcessKw, regimeChange };
    });
    const window12 = allT2.slice(-12);
    const annualSavingNet = window12.reduce((z, i) => {
      const d = qmap.get(Number(consumptionPeriod(i).slice(5, 7)));
      return z + actual(i) - sim(i, d?.kw || currentKw);
    }, 0);
    return { currentKw, tariffCode, minimumKw, rate, rows, annualSaving: annualSavingNet * 1.3, annualSavingNet, optimizationMethod: "t2_quarterly_weighted_smoothed", regimeChange, hasData: allT2.length > 0 && rate > 0 };
  }
`;

s = s.slice(0, a) + block + s.slice(b);
writeFileSync(path, s, "utf8");
console.log("Applied T2 V4 weighted quarterly optimizer.");
