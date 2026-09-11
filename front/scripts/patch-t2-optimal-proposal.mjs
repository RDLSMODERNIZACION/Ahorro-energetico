import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// T2_OPTIMAL_POWER_V2";

if (source.includes(marker)) {
  console.log("T2 optimal-power V2 already applied.");
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
  // T2_OPTIMAL_POWER_V2
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
    latestContract?.current_tariff_code || "",
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
    const t2History = valid
      .filter((invoice) =>
        String(invoice.current_tariff_code || "").toUpperCase().startsWith("T2"),
      )
      .slice(-24);

    const simulatedCost = (candidateKw: number) =>
      t2History.reduce((sum, invoice) => {
        const monthRate = powerRate(invoice) || rate;
        if (!(monthRate > 0)) return sum;
        const demand = values(invoice).demand;
        const excessKw = Math.max(0, Math.round(demand - candidateKw));
        return sum + candidateKw * monthRate + excessKw * monthRate * 1.5;
      }, 0);

    let optimalKw = Math.max(10, Math.min(49, Math.round(currentKw || 10)));
    let optimalCost = Number.POSITIVE_INFINITY;
    for (let candidate = 10; candidate <= 49; candidate += 1) {
      const cost = simulatedCost(candidate);
      if (cost < optimalCost) {
        optimalCost = cost;
        optimalKw = candidate;
      }
    }

    const rows = monthlyRows.map((row) => {
      const latestObservation = row.observations.length
        ? row.observations[row.observations.length - 1]
        : undefined;
      const demand = Number(latestObservation?.demand || 0);
      const actualExcessKw = Math.max(0, Math.round(demand - currentKw));
      const proposedExcessKw = Math.max(0, Math.round(demand - optimalKw));
      const actualCost =
        currentKw * rate + actualExcessKw * rate * 1.5;
      const proposedCost =
        optimalKw * rate + proposedExcessKw * rate * 1.5;
      const savingNet = demand > 0 ? actualCost - proposedCost : 0;
      const saving = savingNet * 1.3;
      return {
        ...row,
        monthlyProposalKw: optimalKw,
        proposalKw: optimalKw,
        quarterlyProposalKw: optimalKw,
        quarter: "T2 · óptimo económico",
        method: "mensual" as const,
        reason:
          proposedExcessKw > 0
            ? `T2 óptimo: ${nf.format(optimalKw)} kW. Este mes proyecta ${nf.format(proposedExcessKw)} kW de EXC, pero el costo total histórico DEM + EXC es menor.`
            : `T2 óptimo: ${nf.format(optimalKw)} kW. Minimiza el costo histórico DEM + EXC.`,
        spreadKw: 0,
        extraCost: 0,
        reducibleKw: Math.max(0, currentKw - optimalKw),
        savingNet,
        saving,
      };
    });

    const actualWindowCost = t2History.slice(-12).reduce((sum, invoice) => {
      const monthRate = powerRate(invoice) || rate;
      if (!(monthRate > 0)) return sum;
      const contracted = contractedBands(invoice).peak || currentKw;
      const demand = values(invoice).demand;
      const excessKw = Math.max(0, Math.round(demand - contracted));
      return sum + contracted * monthRate + excessKw * monthRate * 1.5;
    }, 0);
    const proposedWindowCost = t2History.slice(-12).reduce((sum, invoice) => {
      const monthRate = powerRate(invoice) || rate;
      if (!(monthRate > 0)) return sum;
      const demand = values(invoice).demand;
      const excessKw = Math.max(0, Math.round(demand - optimalKw));
      return sum + optimalKw * monthRate + excessKw * monthRate * 1.5;
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
console.log("Applied T2 optimal single-line proposal V2.");
