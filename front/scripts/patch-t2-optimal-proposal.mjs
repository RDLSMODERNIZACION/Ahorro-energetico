import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// T2_OPTIMAL_POWER_V1";

if (source.includes(marker)) {
  console.log("T2 optimal-power proposal patch already applied.");
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
  // T2_OPTIMAL_POWER_V1
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

  const powerLineAmount = (invoice: Invoice, code: string) =>
    (invoice.invoice_lines || [])
      .filter((line) => String(line.concept_code || "").toUpperCase() === code)
      .reduce((sum, line) => {
        const net = Number(line.net_amount || 0);
        if (net > 0) return sum + net;
        return (
          sum +
          Math.max(0, Number(line.quantity || 0)) *
            Math.max(0, Number(line.unit_price || 0))
        );
      }, 0);
  const lineRate = (invoice: Invoice, code: string) =>
    Math.max(
      0,
      ...(invoice.invoice_lines || [])
        .filter((line) => String(line.concept_code || "").toUpperCase() === code)
        .map((line) => Number(line.unit_price || 0)),
    );
  const tariffOf = (invoice: Invoice) =>
    String(
      invoice.current_tariff_code || invoice.meters?.current_tariff_code || "",
    ).toUpperCase();

  if (tariffCode.startsWith("T2")) {
    const t2History = valid
      .filter((invoice) => tariffOf(invoice).startsWith("T2") && powerRate(invoice) > 0)
      .slice(-24);

    const simulatedPowerCost = (invoice: Invoice, contractedKw: number) => {
      const demRate = lineRate(invoice, "DEM") || powerRate(invoice);
      const excRate = lineRate(invoice, "EXC") || demRate * 1.5;
      if (!(demRate > 0)) return 0;
      const demand = values(invoice).demand;
      // EPEN factura EXC en kW enteros: los casos reales de la base coinciden con redondeo.
      const excessKw = Math.max(0, Math.round(demand - contractedKw));
      return contractedKw * demRate + excessKw * excRate;
    };
    const actualPowerCost = (invoice: Invoice) => {
      const billed = powerLineAmount(invoice, "DEM") + powerLineAmount(invoice, "EXC");
      if (billed > 0) return billed;
      const contracted = contractedBands(invoice).peak;
      return simulatedPowerCost(invoice, contracted);
    };

    let optimalKw = Math.max(10, Math.min(49, Math.round(currentKw || 10)));
    let optimalCost = Number.POSITIVE_INFINITY;
    for (let candidate = 10; candidate <= 49; candidate += 1) {
      const cost = t2History.reduce(
        (sum, invoice) => sum + simulatedPowerCost(invoice, candidate),
        0,
      );
      if (cost < optimalCost - 0.01) {
        optimalCost = cost;
        optimalKw = candidate;
      }
    }

    const monthlyRows = powerMonthNames.map((month, idx) => {
      const monthNumber = idx + 1;
      const observations = latestMonthlyDemands(history, monthNumber);
      const monthInvoices = t2History.filter(
        (invoice) => Number(consumptionPeriod(invoice).slice(5, 7)) === monthNumber,
      );
      const latestMonthInvoice = [...monthInvoices].sort((a, b) =>
        periodOf(b).localeCompare(periodOf(a)),
      )[0];
      const savingNet = latestMonthInvoice
        ? actualPowerCost(latestMonthInvoice) -
          simulatedPowerCost(latestMonthInvoice, optimalKw)
        : 0;
      const maxDemand = observations.length
        ? Math.max(...observations.map((item) => item.demand))
        : 0;
      const projectedExcessKw = Math.max(0, Math.round(maxDemand - optimalKw));
      return {
        month,
        monthNumber,
        observations,
        monthlyProposalKw: optimalKw,
        proposalKw: optimalKw,
        quarterlyProposalKw: optimalKw,
        quarter: "T2 · óptimo económico",
        method: "mensual" as const,
        reason:
          projectedExcessKw > 0
            ? `T2 óptimo: ${nf.format(optimalKw)} kW; admite hasta ${nf.format(projectedExcessKw)} kW de EXC en este mes histórico porque minimiza el costo total del período.`
            : `T2 óptimo: ${nf.format(optimalKw)} kW; minimiza DEM + EXC sobre hasta 24 meses históricos.`,
        spreadKw: 0,
        extraCost: 0,
        reducibleKw: Math.max(0, currentKw - optimalKw),
        savingNet,
        saving: savingNet * 1.3,
        projectedExcessKw,
      };
    });

    const annualWindow = t2History.slice(-12);
    const annualSavingNet = annualWindow.reduce(
      (sum, invoice) =>
        sum + actualPowerCost(invoice) - simulatedPowerCost(invoice, optimalKw),
      0,
    );

    return {
      currentKw,
      tariffCode,
      minimumKw,
      rate,
      rows: monthlyRows,
      annualSaving: annualSavingNet * 1.3,
      annualSavingNet,
      optimalKw,
      optimizationMethod: "t2_dem_plus_exc",
      hasData: t2History.length > 0 && rate > 0,
    };
  }

  const monthlyRows = powerMonthNames.map((month, idx) => {
    const monthNumber = idx + 1;
    const observations = latestMonthlyDemands(history, monthNumber);
    const monthlyProposalKw = observations.length
      ? Math.max(minimumKw, ...observations.map((x) => x.demand))
      : 0;
    return { month, monthNumber, observations, monthlyProposalKw };
  });
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
        sum +
        Math.max(0, quarterlyProposalKw - row.monthlyProposalKw) * rate * 1.3,
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
    const reducibleKw =
      proposalKw > 0 ? Math.max(0, currentKw - proposalKw) : 0;
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
console.log("Applied T2 economic optimum: DEM + EXC over up to 24 months.");
