import { readFileSync, writeFileSync } from "node:fs";

const panelPath = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(panelPath, "utf8");

const slotNeedle = `  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);`;
if (!source.includes("SAME_MONTH_PEER_SELECTION_V2")) {
  if (!source.includes(slotNeedle)) throw new Error("InvoiceTrend slot block not found");
  source = source.replace(
    slotNeedle,
    `  // SAME_MONTH_PEER_SELECTION_V2\n  const selectedConsumptionPeriod = data.find((d) => d.billingPeriod === selectedPeriod)?.period || \"\";\n  const selectedConsumptionMonth = selectedConsumptionPeriod.slice(5, 7);\n  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);`,
  );

  const oldSelected = '${selectedPeriod === d.billingPeriod ? " selected" : ""}`}' ;
  const newSelected = '${selectedPeriod === d.billingPeriod ? " selected" : selectedConsumptionMonth && d.period.slice(5, 7) === selectedConsumptionMonth ? " same-month" : ""}`}' ;
  if (!source.includes(oldSelected)) throw new Error("InvoiceTrend selected class expression not found");
  source = source.replace(oldSelected, newSelected);

  const oldTitle = `<h3>Evolución histórica del medidor</h3>`;
  const newTitle = `<h3 style={{display:"flex",alignItems:"baseline",gap:8,flexWrap:"wrap"}}>\n                <span>Evolución histórica del medidor</span>\n                <small style={{fontSize:11,fontWeight:700,color:"#78857f"}}>/ {new Intl.DateTimeFormat("es-AR", { month: "long" }).format(new Date(Date.UTC(Number(consumptionPeriod(selected).slice(0,4)), Number(consumptionPeriod(selected).slice(5,7)) - 1, 1)))} / {consumptionPeriod(selected).slice(5,7)} / {consumptionPeriod(selected).slice(0,4)}</small>\n              </h3>`;
  if (!source.includes(oldTitle)) throw new Error("Historical chart title not found");
  source = source.replace(oldTitle, newTitle);
  writeFileSync(panelPath, source, "utf8");
}

const cssPath = new URL("../app/globals.css", import.meta.url);
let css = readFileSync(cssPath, "utf8");
if (!css.includes("SAME_MONTH_PEER_SELECTION_V2")) {
  css += `\n\n/* SAME_MONTH_PEER_SELECTION_V2 */\n.invoice-analysis-bar.same-month rect { opacity: .68; stroke: #2f8f6b; stroke-width: 2px; filter: saturate(.78); }\n.invoice-analysis-bar.same-month:hover rect { opacity: .86; }\n.invoice-analysis-bar.selected rect { opacity: 1 !important; stroke-width: 0 !important; filter: none !important; }\n`;
  writeFileSync(cssPath, css, "utf8");
}

console.log("Applied same-month peer highlight v2 and selected month label.");
