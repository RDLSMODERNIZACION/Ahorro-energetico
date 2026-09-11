import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// T2_OPTIMAL_POWER_V3_QUARTERLY";

if (source.includes(marker)) {
  console.log("T2 quarterly optimal-power V3 already applied.");
  process.exit(0);
}

const startNeedle = "function buildPowerCurve(history: Invoice[]) {";
const endNeedle = "\n}\n\nexport function calculateCanonicalSavings";
const start = source.indexOf(startNeedle);
const end = source.indexOf(endNeedle, start);
if (start < 0 || end < 0) {
  throw new Error("Could not locate buildPowerCurve in invoice-analysis-panel.tsx");
}

const replacement = `function buildPowerCurve(history: Invoice[]) {
  // T2_OPTIMAL_POWER_V3_QUARTERLY
  const valid = history
    .filter((i) => values(i).demand > 0)
    .sort((a, b) => periodOf(a).localeCompare(periodOf(b)));
  const latestContract = [...valid]
    .reverse()
    .find((i) => contractedBands(i).peak > 0);
  const latestRateInvoice = [...valid].reverse().find((i) => powerRate(i) > 0);
  const currentKw = Number(
    latestContract ? contractedBands(latestContract).peak : 0,
  );
  const tariffCode = String(
    latestContract?.current_tariff_code ||
      latestContract?.meters?.current_tariff_code ||
      "",
  ).toUpperCase();
  const minimumKw = minimumContractedKw(tariffCode);
  const rate = Number(latestRateInvoice ? powerRate(latestRateInvoice) : 0);
  const monthlyRows = powerMonthNames.map((month, idx) => {
    const monthNumber = idx + 1;
    const observations = latestMonthlyDemands(history, monthNumber);
    const monthlyProposalKw = observations.length
      ? Math.max(minimumKw, ...observations.map((x) => x.demand))
      : 0;
    return { month, monthNumber, observations, monthlyProposalKw };
  });

  if (tariffCode.startsWith("T2")) {
    const tariffOf = (invoice: Invoice) =>
      String(
        invoice.current_tariff_code ||
          invoice.meters?.current_tariff_code ||
          "",
      ).toUpperCase();
    const lineRate = (invoice: Invoice, code: string) =>
      Math.max(
        0,
        ...(invoice.invoice_lines || [])
          .filter(
            (line) =>
              String(line.concept_code || "").toUpperCase() === code,
          )
          .map((line) => Number(line.unit_price || 0)),
      );
    const lineAmount = (invoice: Invoice, code: string) =>
      (invoice.invoice_lines || [])
        .filter(
          (line) => String(line.concept_code || "").toUpperCase() === code,
        )
        .reduce((sum, line) => {
          const net = Number(line.net_amount || 0);
          if (net > 0) return sum + net;
          return (
            sum +
            Math.max(0, Number(line.quantity || 0)) *
              Math.max(0, Number(line.unit_price || 0))
          );
        }, 0);

    const t2History = valid
      .filter(
        (invoice) =>
          tariffOf(invoice).startsWith("T2") && powerRate(invoice) > 0,
      )
      .slice(-24);

    const simulatedPowerCost = (invoice: Invoice, contractedKw: number) => {
      const demRate = lineRate(invoice, "DEM") || powerRate(invoice) || rate;
      const excRate = lineRate(invoice, "EXC") || demRate * 1.5;
      if (!(demRate > 0)) return 0;
      const demand = values(invoice).demand;
      const excessKw = Math.max(0, Math.round(demand - contractedKw));
      return contractedKw * demRate + excessKw * excRate;
    };
    const actualPowerCost = (invoice: Invoice) => {
      const billed = lineAmount(invoice, "DEM") + lineAmount(invoice, "EXC");
      if (billed > 0) return billed;
      const contracted = contractedBands(invoice).peak || currentKw;
      return simulatedPowerCost(invoice, contracted);
    };

    const quarterlyOptimum = new Map<
      number,
      {
        optimalKw: number;
        quarter: string;
        sampleCount: number;
        historicalCost: number;
      }
    >();

    for (const quarter of epenPowerQuarters) {
      const quarterHistory = t2History.filter((invoice) =>
        quarter.months.includes(Number(consumptionPeriod(invoice).slice(5, 7))),
      );
      let optimalKw = Math.max(
        10,
        Math.min(49, Math.round(currentKw || 10)),
      );
      let optimalCost = Number.POSITIVE_INFINITY;
      for (let candidate = 10; candidate <= 49; candidate += 1) {
        const cost = quarterHistory.reduce(
          (sum, invoice) => sum + simulatedPowerCost(invoice, candidate),
          0,
        );
        if (quarterHistory.length > 0 && cost < optimalCost - 0.01) {
          optimalCost = cost;
          optimalKw = candidate;
        }
      }
      if (!quarterHistory.length) optimalCost = 0;
      for (const monthNumber of quarter.months) {
        quarterlyOptimum.set(monthNumber, {
          optimalKw,
          quarter: quarter.label,
          sampleCount: quarterHistory.length,
          historicalCost: optimalCost,
        });
      }
    }

    const rows = monthlyRows.map((row) => {
      const decision = quarterlyOptimum.get(row.monthNumber)!;
      const proposalKw = decision.optimalKw;
      const monthInvoices = t2History.filter(
        (invoice) =>
          Number(consumptionPeriod(invoice).slice(5, 7)) === row.monthNumber,
      );
      const latestMonthInvoice = [...monthInvoices].sort((a, b) =>
        periodOf(b).localeCompare(periodOf(a)),
      )[0];
      const demand = latestMonthInvoice
        ? values(latestMonthInvoice).demand
        : row.observations.length
          ? Number(row.observations[row.observations.length - 1]?.demand || 0)
          : 0;
      const projectedExcessKw = Math.max(0, Math.round(demand - proposalKw));
      const savingNet = latestMonthInvoice
        ? actualPowerCost(latestMonthInvoice) -
          simulatedPowerCost(latestMonthInvoice, proposalKw)
        : 0;
      return {
        ...row,
        monthlyProposalKw: proposalKw,
        proposalKw,
        quarterlyProposalKw: proposalKw,
        quarter: decision.quarter,
        method: "trimestral" as const,
        reason:
          projectedExcessKw > 0
            ? `T2 óptimo trimestral ${decision.quarter}: ${nf.format(proposalKw)} kW. Este mes proyecta ${nf.format(projectedExcessKw)} kW de EXC, aceptado porque minimiza el costo total DEM + EXC del trimestre histórico.`
            : `T2 óptimo trimestral ${decision.quarter}: ${nf.format(proposalKw)} kW. Minimiza DEM + EXC usando ${nf.format(decision.sampleCount)} factura(s) histórica(s) del mismo trimestre.`,
        spreadKw: 0,
        extraCost: 0,
        reducibleKw: Math.max(0, currentKw - proposalKw),
        savingNet,
        saving: savingNet * 1.3,
        projectedExcessKw,
      };
    });

    const annualWindow = t2History.slice(-12);
    const actualWindowCost = annualWindow.reduce(
      (sum, invoice) => sum + actualPowerCost(invoice),
      0,
    );
    const proposedWindowCost = annualWindow.reduce((sum, invoice) => {
      const monthNumber = Number(consumptionPeriod(invoice).slice(5, 7));
      const proposalKw = quarterlyOptimum.get(monthNumber)?.optimalKw || currentKw;
      return sum + simulatedPowerCost(invoice, proposalKw);
    }, 0);
    const annualSavingNet = actualWindowCost - proposedWindowCost;

    return {
      currentKw,
      tariffCode,
      minimumKw,
      rate,
      rows,
      annualSaving: annualSavingNet * 1.3,
      annualSavingNet,
      optimizationMethod: "t2_quarterly_dem_plus_exc",
      hasData: t2History.length > 0 && rate > 0,
    };
  }

  const quarterlyDecision = new Map<
    number,
    {
      proposalKw: number;
      quarterlyProposalKw: number;
      quarter: string;
      method: "trimestral" | "mensual";
      reason: string;
      spreadKw: number;
      extraCost: number;
    }
  >();
  for (const quarter of epenPowerQuarters) {
    const quarterRows = quarter.months.map((month) =>
      monthlyRows.find((row) => row.monthNumber === month)!,
    );
    const complete = quarterRows.every((row) => row.monthlyProposalKw > 0);
    const proposals = quarterRows
      .map((row) => row.monthlyProposalKw)
      .filter((value) => value > 0);
    const quarterlyProposalKw = proposals.length ? Math.max(...proposals) : 0;
    const spreadKw = proposals.length
      ? quarterlyProposalKw - Math.min(...proposals)
      : 0;
    const monthlySaving = quarterRows.reduce(
      (sum, row) =>
        sum + Math.max(0, currentKw - row.monthlyProposalKw) * rate * 1.3,
      0,
    );
    const extraCost = quarterRows.reduce(
      (sum, row) =>
        sum + Math.max(0, quarterlyProposalKw - row.monthlyProposalKw) * rate * 1.3,
      0,
    );
    const economicLimit = monthlySaving * 0.1;
    const useQuarter = complete && spreadKw <= 10 && extraCost <= economicLimit;
    const reason = !complete
      ? "Mes a mes: faltan datos en el trimestre"
      : spreadKw > 10
        ? `Mes a mes: diferencia trimestral de ${nf.format(spreadKw)} kW (>10 kW)`
        : extraCost > economicLimit
          ? `Mes a mes: el costo extra supera el 10% del ahorro mensual`
          : "Trimestral EPEN: diferencia ≤10 kW y costo extra ≤10% del ahorro";
    for (const row of quarterRows) {
      quarterlyDecision.set(row.monthNumber, {
        proposalKw: useQuarter ? quarterlyProposalKw : row.monthlyProposalKw,
        quarterlyProposalKw,
        quarter: quarter.label,
        method: useQuarter ? "trimestral" : "mensual",
        reason,
        spreadKw,
        extraCost,
      });
    }
  }
  const rows = monthlyRows.map((row) => {
    const decision = quarterlyDecision.get(row.monthNumber)!;
    const proposalKw = decision.proposalKw;
    const reducibleKw = proposalKw > 0 ? Math.max(0, currentKw - proposalKw) : 0;
    const savingNet = reducibleKw * rate;
    const saving = savingNet * 1.3;
    return { ...row, ...decision, proposalKw, reducibleKw, savingNet, saving };
  });
  return {
    currentKw,
    tariffCode,
    minimumKw,
    rate,
    rows,
    annualSaving: rows.reduce((sum, row) => sum + row.saving, 0),
    annualSavingNet: rows.reduce((sum, row) => sum + row.savingNet, 0),
    hasData:
      currentKw > 0 && rate > 0 && rows.some((row) => row.proposalKw > 0),
  };
}`;

source = source.slice(0, start) + replacement + source.slice(end + 2);
writeFileSync(path, source, "utf8");
console.log("Applied T2 quarterly economic optimum: DEM + EXC by EPEN quarter.");
