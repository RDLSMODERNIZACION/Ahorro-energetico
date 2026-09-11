import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// T2_EXCESS_BAR_V2";

if (source.includes(marker)) {
  console.log("T2 excess-demand bar patch already applied.");
  process.exit(0);
}

const oldData = `        pfUnknownPenalized: values(invoice).pfUnknownPenalized,\n        penalized: values(invoice).penalized,\n      }));`;
const newData = `        pfUnknownPenalized: values(invoice).pfUnknownPenalized,\n        penalized: values(invoice).penalized,\n        // T2_EXCESS_BAR_V2\n        tariffCode: String(invoice.current_tariff_code || invoice.meters?.current_tariff_code || \"\").toUpperCase(),\n        excessKw: (invoice.invoice_lines || [])\n          .filter((line) => String(line.concept_code || \"\").toUpperCase() === \"EXC\")\n          .reduce((sum, line) => sum + Math.max(0, Number(line.quantity || 0)), 0),\n      }));`;

if (!source.includes(oldData)) {
  throw new Error("Could not locate InvoiceTrend data block for T2 excess patch.");
}
source = source.replace(oldData, newData);

const oldMapStart = `        {data.map((d, index) => {\n          const x = left + index * slot + (slot - bw) / 2;\n          const graphValue =\n            metric === \"pf\" && d.pfUnknownPenalized ? 0.95 : d.value;\n          const y = top + plotH - (graphValue / max) * plotH;\n          return (`;
const newMapStart = `        {data.map((d, index) => {\n          const x = left + index * slot + (slot - bw) / 2;\n          const graphValue =\n            metric === \"pf\" && d.pfUnknownPenalized ? 0.95 : d.value;\n          const y = top + plotH - (graphValue / max) * plotH;\n          const isT2Demand = metric === \"demand\" && d.tariffCode.startsWith(\"T2\");\n          const proposedExcessKw =\n            powerLine === \"proposal\" && d.proposed > 0\n              ? Math.max(0, Math.round(d.value - d.proposed))\n              : 0;\n          const currentExcessKw = d.excessKw > 0\n            ? d.excessKw\n            : Math.max(0, Math.round(d.value - d.contracted));\n          const t2ExcessKw =\n            powerLine === \"proposal\" ? proposedExcessKw : currentExcessKw;\n          const t2Excess = isT2Demand && t2ExcessKw > 0;\n          return (`;

if (!source.includes(oldMapStart)) {
  throw new Error("Could not locate InvoiceTrend render block for T2 excess patch.");
}
source = source.replace(oldMapStart, newMapStart);

const oldRect = `              <rect\n                x={x}\n                y={y}\n                width={bw}\n                height={Math.max(2, top + plotH - y)}\n                rx=\"5\"\n              >\n                <title>\n                  {metric === \"pf\" && d.pfUnknownPenalized\n                    ? \`Consumo \${d.period} · Factura \${d.billingPeriod} · Penalización de factor de potencia · cos φ no informado\`\n                    : \`Consumo \${d.period} · Factura \${d.billingPeriod} · \${fmt(metric, d.value)}\`}\n                </title>\n              </rect>`;
const newRect = `              <rect\n                x={x}\n                y={y}\n                width={bw}\n                height={Math.max(2, top + plotH - y)}\n                rx=\"5\"\n                style={t2Excess ? { fill: \"#dc2626\" } : undefined}\n              >\n                <title>\n                  {metric === \"pf\" && d.pfUnknownPenalized\n                    ? \`Consumo \${d.period} · Factura \${d.billingPeriod} · Penalización de factor de potencia · cos φ no informado\`\n                    : t2Excess && powerLine === \"proposal\"\n                      ? \`Consumo \${d.period} · Factura \${d.billingPeriod} · T2 · Demanda \${fmt(metric, d.value)} · Propuesta \${nf.format(d.proposed)} kW · EXC proyectado \${nf.format(t2ExcessKw)} kW\`\n                      : t2Excess\n                        ? \`Consumo \${d.period} · Factura \${d.billingPeriod} · T2 · Demanda \${fmt(metric, d.value)} · Contratada \${nf.format(d.contracted)} kW · Exceso \${nf.format(t2ExcessKw)} kW facturado con EXC\`\n                        : \`Consumo \${d.period} · Factura \${d.billingPeriod} · \${fmt(metric, d.value)}\`}\n                </title>\n              </rect>`;

if (!source.includes(oldRect)) {
  throw new Error("Could not locate InvoiceTrend rect block for T2 excess patch.");
}
source = source.replace(oldRect, newRect);

const oldLegend = `          {powerLine === \"current\" ? (\n            <span>\n              <i className=\"current\" />\n              Contratada actual\n            </span>\n          ) : (\n            <span>\n              <i className=\"proposal\" />\n              Contratada propuesta · mes seleccionado marcado\n            </span>\n          )}`;
const newLegend = `          {powerLine === \"current\" ? (\n            <>\n              <span>\n                <i className=\"current\" />\n                Contratada actual\n              </span>\n              <span>\n                <i style={{ background: \"#dc2626\" }} />\n                T2 con exceso de demanda facturado (EXC)\n              </span>\n            </>\n          ) : (\n            <>\n              <span>\n                <i className=\"proposal\" />\n                Contratada propuesta óptima · mes seleccionado marcado\n              </span>\n              <span>\n                <i style={{ background: \"#dc2626\" }} />\n                T2 con EXC proyectado bajo la propuesta\n              </span>\n            </>\n          )}`;

if (!source.includes(oldLegend)) {
  throw new Error("Could not locate power legend for T2 excess patch.");
}
source = source.replace(oldLegend, newLegend);

writeFileSync(path, source, "utf8");
console.log("Applied T2 current/proposed excess-demand red-bar patch.");
