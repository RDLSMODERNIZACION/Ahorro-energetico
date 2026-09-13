import { readFileSync, writeFileSync } from "node:fs";

const panelPath = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(panelPath, "utf8");
const marker = "// SAME_MONTH_PEER_SELECTION_V1";

if (!source.includes(marker)) {
  const slotNeedle = `  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);`;
  const slotReplacement = `  // SAME_MONTH_PEER_SELECTION_V1\n  const selectedConsumptionMonth =\n    data.find((d) => d.billingPeriod === selectedPeriod)?.period.slice(5, 7) || \"\";\n  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);`;
  if (!source.includes(slotNeedle)) throw new Error("InvoiceTrend slot block not found");
  source = source.replace(slotNeedle, slotReplacement);

  const classNeedle = '${selectedPeriod === d.billingPeriod ? " selected" : ""}`}' ;
  const classReplacement = '${selectedPeriod === d.billingPeriod ? " selected" : selectedConsumptionMonth && d.period.slice(5, 7) === selectedConsumptionMonth ? " same-month" : ""}`}' ;
  if (!source.includes(classNeedle)) throw new Error("InvoiceTrend selected class expression not found");
  source = source.replace(classNeedle, classReplacement);

  writeFileSync(panelPath, source, "utf8");
}

const cssPath = new URL("../app/globals.css", import.meta.url);
let css = readFileSync(cssPath, "utf8");
const cssMarker = "/* SAME_MONTH_PEER_SELECTION_V1 */";
if (!css.includes(cssMarker)) {
  css += `\n\n${cssMarker}\n.invoice-analysis-bar.same-month rect {\n  opacity: 0.72;\n  stroke: #146b49;\n  stroke-width: 1.5px;\n}\n.invoice-analysis-bar.same-month:hover rect {\n  opacity: 0.9;\n}\n`;
  writeFileSync(cssPath, css, "utf8");
}

console.log("Added subtle highlighting for bars from the same calendar month as the selected invoice.");
