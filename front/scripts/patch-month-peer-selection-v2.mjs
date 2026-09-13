import { readFileSync, writeFileSync } from "node:fs";

const panelPath = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(panelPath, "utf8");

const slotNeedle = `  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);`;
if (!source.includes("SAME_MONTH_PEER_SELECTION_V3")) {
  if (!source.includes(slotNeedle)) throw new Error("InvoiceTrend slot block not found");
  source = source.replace(
    slotNeedle,
    `  // SAME_MONTH_PEER_SELECTION_V3\n  const selectedBillingMonth = String(selectedPeriod || \"\").slice(5, 7);\n  const slot = plotW / Math.max(1, data.length),\n    bw = Math.max(12, slot * 0.58);`,
  );

  const mapNeedle = `          const y = top + plotH - (graphValue / max) * plotH;`;
  if (!source.includes(mapNeedle)) throw new Error("InvoiceTrend map y block not found");
  source = source.replace(
    mapNeedle,
    mapNeedle + `\n          const sameBillingMonthPeer =\n            selectedPeriod !== d.billingPeriod &&\n            selectedBillingMonth &&\n            String(d.billingPeriod || \"\").slice(5, 7) === selectedBillingMonth;`,
  );

  const styleNeedle = `                style={t2Excess ? { fill: \"#dc2626\" } : undefined}`;
  if (!source.includes(styleNeedle)) throw new Error("InvoiceTrend bar style block not found");
  source = source.replace(
    styleNeedle,
    `                style={\n                  sameBillingMonthPeer\n                    ? {\n                        fill: \"#63b78f\",\n                        opacity: 0.72,\n                        stroke: \"#146b49\",\n                        strokeWidth: 3,\n                      }\n                    : t2Excess\n                      ? { fill: \"#dc2626\" }\n                      : undefined\n                }`,
  );

  const oldTitle = `<h3>Evolución histórica del medidor</h3>`;
  const newTitle = `<h3 style={{display:"flex",alignItems:"baseline",gap:8,flexWrap:"wrap"}}>\n                <span>Evolución histórica del medidor</span>\n                <small style={{fontSize:11,fontWeight:700,color:"#78857f"}}>/ {new Intl.DateTimeFormat("es-AR", { month: "long" }).format(new Date(Date.UTC(Number(selectedPeriod.slice(0,4)), Number(selectedPeriod.slice(5,7)) - 1, 1)))} / {selectedPeriod.slice(5,7)} / {selectedPeriod.slice(0,4)}</small>\n              </h3>`;
  if (source.includes(oldTitle)) source = source.replace(oldTitle, newTitle);

  writeFileSync(panelPath, source, "utf8");
}

console.log("Applied visible same-billing-month peer highlight and selected period label.");
