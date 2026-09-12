import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// T2_PROPOSAL_SAVINGS_V1";

if (source.includes(marker)) {
  console.log("T2 proposal savings summary already applied.");
  process.exit(0);
}

const calcNeedle = `  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);\n\n  return (`;

const calcReplacement = [
  `  const slot = plotW / Math.max(1, data.length),`,
  `    bw = Math.max(12, slot * 0.58);`,
  ``,
  `  // T2_PROPOSAL_SAVINGS_V1`,
  `  const t2ProposalSummary = useMemo(() => {`,
  `    if (metric !== "demand" || powerLine !== "proposal") return null;`,
  `    const t2 = data.filter((d) => d.tariffCode?.startsWith("T2") && d.proposed > 0);`,
  `    if (!t2.length) return null;`,
  ``,
  `    const lineRate = (invoice: Invoice, code: string) =>`,
  `      Math.max(`,
  `        0,`,
  `        ...(invoice.invoice_lines || [])`,
  `          .filter((line) => String(line.concept_code || "").toUpperCase() === code)`,
  `          .map((line) => Number(line.unit_price || 0)),`,
  `      );`,
  `    const lineAmount = (invoice: Invoice, code: string) =>`,
  `      (invoice.invoice_lines || [])`,
  `        .filter((line) => String(line.concept_code || "").toUpperCase() === code)`,
  `        .reduce((sum, line) => {`,
  `          const net = Number(line.net_amount || 0);`,
  `          return sum + (net > 0 ? net : Math.max(0, Number(line.quantity || 0)) * Math.max(0, Number(line.unit_price || 0)));`,
  `        }, 0);`,
  `    const sim = (invoice: Invoice, contractedKw: number, demandKw: number, fallbackDem?: number, fallbackExc?: number) => {`,
  `      const dem = lineRate(invoice, "DEM") || Number(fallbackDem || 0);`,
  `      const exc = lineRate(invoice, "EXC") || Number(fallbackExc || 0) || dem * 1.5;`,
  `      if (!(dem > 0)) return 0;`,
  `      const over = Math.max(0, Math.round(Math.max(0, demandKw) - contractedKw));`,
  `      return contractedKw * dem + over * exc;`,
  `    };`,
  `    const actual = (invoice: Invoice, demandKw: number) => {`,
  `      const billed = lineAmount(invoice, "DEM") + lineAmount(invoice, "EXC");`,
  `      if (billed > 0) return billed;`,
  `      return sim(invoice, contractedBands(invoice).peak, demandKw);`,
  `    };`,
  ``,
  `    const last12 = t2.slice(-12);`,
  `    const historicalNet = last12.reduce((sum, d) => {`,
  `      const proposed = Number(d.proposed || 0);`,
  `      return sum + actual(d.invoice, Number(d.value || 0)) - sim(d.invoice, proposed, Number(d.value || 0));`,
  `    }, 0);`,
  ``,
  `    const latest = t2[t2.length - 1];`,
  `    const currentKw = Number(latest?.contracted || 0);`,
  `    const latestDemRate = latest ? lineRate(latest.invoice, "DEM") : 0;`,
  `    const latestExcRate = latest ? lineRate(latest.invoice, "EXC") || latestDemRate * 1.5 : 0;`,
  `    if (!(currentKw > 0) || !(latestDemRate > 0)) {`,
  `      return { historicalNet, projectedBaseNet: 0, projectedLowNet: 0, projectedHighNet: 0, regimeChange: false };`,
  `    }`,
  ``,
  `    const recent = t2.slice(-3).map((d) => Number(d.value || 0));`,
  `    const previous = t2.slice(-12, -3).map((d) => Number(d.value || 0));`,
  `    const avg = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;`,
  `    const ratio = avg(previous) > 0 ? avg(recent) / avg(previous) : 1;`,
  `    const regimeChange = previous.length >= 3 && (ratio <= 0.65 || ratio >= 1.35);`,
  ``,
  `    let projectedBaseNet = 0;`,
  `    let projectedConservativeNet = 0;`,
  `    let projectedOptimisticNet = 0;`,
  `    for (let month = 1; month <= 12; month += 1) {`,
  `      const monthRows = t2.filter((d) => Number(d.period.slice(5, 7)) === month);`,
  `      if (!monthRows.length) continue;`,
  `      const last = Number(monthRows[monthRows.length - 1]?.value || 0);`,
  `      const prior = Number(monthRows[monthRows.length - 2]?.value ?? last);`,
  `      const baseDemand = regimeChange ? 0.8 * last + 0.2 * prior : 0.6 * last + 0.4 * prior;`,
  `      const conservativeDemand = Math.max(last, prior);`,
  `      const optimisticDemand = Math.min(last, prior);`,
  `      const proposedKw = Number(monthRows[monthRows.length - 1]?.proposed || currentKw);`,
  `      const fake = latest.invoice;`,
  `      const currentBase = sim(fake, currentKw, baseDemand, latestDemRate, latestExcRate);`,
  `      const proposedBase = sim(fake, proposedKw, baseDemand, latestDemRate, latestExcRate);`,
  `      const currentConservative = sim(fake, currentKw, conservativeDemand, latestDemRate, latestExcRate);`,
  `      const proposedConservative = sim(fake, proposedKw, conservativeDemand, latestDemRate, latestExcRate);`,
  `      const currentOptimistic = sim(fake, currentKw, optimisticDemand, latestDemRate, latestExcRate);`,
  `      const proposedOptimistic = sim(fake, proposedKw, optimisticDemand, latestDemRate, latestExcRate);`,
  `      projectedBaseNet += currentBase - proposedBase;`,
  `      projectedConservativeNet += currentConservative - proposedConservative;`,
  `      projectedOptimisticNet += currentOptimistic - proposedOptimistic;`,
  `    }`,
  `    return {`,
  `      historicalNet,`,
  `      projectedBaseNet,`,
  `      projectedLowNet: Math.min(projectedConservativeNet, projectedOptimisticNet),`,
  `      projectedHighNet: Math.max(projectedConservativeNet, projectedOptimisticNet),`,
  `      regimeChange,`,
  `    };`,
  `  }, [data, metric, powerLine]);`,
  ``,
  `  return (`,
].join("\n");

if (!source.includes(calcNeedle)) {
  throw new Error("Could not locate InvoiceTrend chart geometry for T2 proposal savings patch.");
}
source = source.replace(calcNeedle, calcReplacement);

const uiNeedle = `      {metric === "demand" && (\n        <div className="invoice-power-legend">`;
const uiReplacement = [
  `      {metric === "demand" && powerLine === "proposal" && t2ProposalSummary && (`,
  `        <div`,
  `          style={{`,
  `            display: "grid",`,
  `            gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",`,
  `            gap: 12,`,
  `            margin: "12px 0 8px",`,
  `          }}`,
  `        >`,
  `          <article style={{ border: "1px solid #dbe5df", borderRadius: 12, padding: 14, background: "#fff" }}>`,
  `            <small style={{ display: "block", color: "#64746d", fontWeight: 700 }}>AHORRO ANUAL HISTÓRICO SIMULADO</small>`,
  `            <b style={{ display: "block", marginTop: 5, fontSize: 22 }}>{money.format(t2ProposalSummary.historicalNet * 1.3)}</b>`,
  `            <span style={{ color: "#64746d", fontSize: 12 }}>{money.format(t2ProposalSummary.historicalNet)} netos · últimos 12 meses reales</span>`,
  `          </article>`,
  `          <article style={{ border: "1px solid #bfd8cb", borderRadius: 12, padding: 14, background: "#f4fbf7" }}>`,
  `            <small style={{ display: "block", color: "#276749", fontWeight: 700 }}>AHORRO ANUAL PROYECTADO · BASE</small>`,
  `            <b style={{ display: "block", marginTop: 5, fontSize: 22 }}>{money.format(t2ProposalSummary.projectedBaseNet * 1.3)}</b>`,
  `            <span style={{ color: "#64746d", fontSize: 12 }}>{money.format(t2ProposalSummary.projectedBaseNet)} netos · a tarifa de potencia actual</span>`,
  `          </article>`,
  `          <article style={{ border: "1px solid #dbe5df", borderRadius: 12, padding: 14, background: "#fff" }}>`,
  `            <small style={{ display: "block", color: "#64746d", fontWeight: 700 }}>RANGO PROYECTADO</small>`,
  `            <b style={{ display: "block", marginTop: 5, fontSize: 18 }}>{money.format(t2ProposalSummary.projectedLowNet * 1.3)} – {money.format(t2ProposalSummary.projectedHighNet * 1.3)}</b>`,
  `            <span style={{ color: "#64746d", fontSize: 12 }}>escenarios conservador y optimista</span>`,
  `          </article>`,
  `          <div style={{ gridColumn: "1 / -1", fontSize: 12, color: "#64746d", lineHeight: 1.45 }}>`,
  `            T2: la proyección es orientativa porque depende de la demanda máxima futura y del EXC. El escenario base combina 60% del dato reciente y 40% del mismo mes previo; si se detecta un cambio fuerte de patrón usa 80% reciente y 20% histórico. Los valores con impuestos aplican el +30% utilizado actualmente por la app.`,
  `            {t2ProposalSummary.regimeChange ? " Cambio reciente de patrón detectado." : ""}`,
  `          </div>`,
  `        </div>`,
  `      )}`,
  ``,
  `      {metric === "demand" && (`,
  `        <div className="invoice-power-legend">`,
].join("\n");

if (!source.includes(uiNeedle)) {
  throw new Error("Could not locate demand legend for T2 proposal savings UI patch.");
}
source = source.replace(uiNeedle, uiReplacement);

writeFileSync(path, source, "utf8");
console.log("Applied T2 historical/projected annual savings summary.");
