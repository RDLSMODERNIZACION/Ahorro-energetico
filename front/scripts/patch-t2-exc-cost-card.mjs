import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// T2_EXC_COST_CARD_V1";

if (source.includes(marker)) {
  console.log("T2 EXC cost card patch already applied.");
  process.exit(0);
}

const oldPowerMonthly = `  const powerMonthly = Number(\n    curve.rows.find((row) => row.monthNumber === monthNumber)?.saving || 0,\n  );`;
const newPowerMonthly = `  // T2_EXC_COST_CARD_V1\n  const powerMonthlyRaw = Number(\n    curve.rows.find((row) => row.monthNumber === monthNumber)?.saving || 0,\n  );\n  // Una oportunidad de ahorro mensual no puede mostrarse negativa.\n  // Si la propuesta cuesta más en ese mes, se informa como costo y el ahorro del mes queda en cero.\n  const powerMonthly = Math.max(0, powerMonthlyRaw);`;

if (!source.includes(oldPowerMonthly)) {
  throw new Error("Could not locate canonical powerMonthly calculation.");
}
source = source.replace(oldPowerMonthly, newPowerMonthly);

const selectedNeedle = `  const v = values(selected);`;
const selectedReplacement = `  const v = values(selected);\n  const selectedTariffCode = String(\n    selected.current_tariff_code || selected.meters?.current_tariff_code || "",\n  ).toUpperCase();\n  const isSelectedT2 = selectedTariffCode.startsWith("T2");\n  const t2ExcessQty = isSelectedT2\n    ? (selected.invoice_lines || [])\n        .filter((line) => String(line.concept_code || "").toUpperCase() === "EXC")\n        .reduce((sum, line) => sum + Math.max(0, Number(line.quantity || 0)), 0)\n    : 0;\n  const t2ExcessCostNet = isSelectedT2\n    ? (selected.invoice_lines || [])\n        .filter((line) => String(line.concept_code || "").toUpperCase() === "EXC")\n        .reduce((sum, line) => sum + Math.max(0, Number(line.net_amount || 0)), 0)\n    : 0;\n  const t2ExcessCostWithTax = t2ExcessCostNet * 1.3;`;

if (!source.includes(selectedNeedle)) {
  throw new Error("Could not locate selected invoice values block.");
}
source = source.replace(selectedNeedle, selectedReplacement);

const opportunityNeedle = `              <div>\n                <span>Factor de potencia</span>`;
const opportunityReplacement = `              {isSelectedT2 && t2ExcessCostNet > 0 && (\n                <div>\n                  <span>Exceso de demanda (EXC)</span>\n                  <b style={{ color: "#b91c1c" }}>\n                    Costo {money.format(t2ExcessCostWithTax)}\n                  </b>\n                  <small>\n                    {nf.format(t2ExcessQty)} kW de exceso · {money.format(t2ExcessCostNet)} netos facturados en esta factura · +30% según criterio actual de la app\n                  </small>\n                </div>\n              )}\n              <div>\n                <span>Factor de potencia</span>`;

if (!source.includes(opportunityNeedle)) {
  throw new Error("Could not locate opportunities list for EXC cost card.");
}
source = source.replace(opportunityNeedle, opportunityReplacement);

writeFileSync(path, source, "utf8");
console.log("Applied T2 EXC invoice-cost card and clamped negative monthly power savings.");
