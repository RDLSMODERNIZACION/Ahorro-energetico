import { readFileSync, writeFileSync } from "node:fs";

const panelPath = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(panelPath, "utf8");

if (!source.includes("SAME_MONTH_PEER_SELECTION_V4")) {
  const mapNeedle = `          const y = top + plotH - (graphValue / max) * plotH;`;
  if (!source.includes(mapNeedle)) throw new Error("InvoiceTrend map y block not found");
  source = source.replace(
    mapNeedle,
    mapNeedle + `\n          // SAME_MONTH_PEER_SELECTION_V4\n          const selectedPeerMonth = (data.find((x) => x.billingPeriod === selectedPeriod)?.period || \"\").slice(5, 7);\n          const sameMonthPeer =\n            selectedPeriod !== d.billingPeriod &&\n            selectedPeerMonth !== \"\" &&\n            String(d.period || \"\").slice(5, 7) === selectedPeerMonth;`,
  );

  const styleNeedle = `                style={t2Excess ? { fill: \"#dc2626\" } : undefined}`;
  if (!source.includes(styleNeedle)) throw new Error("InvoiceTrend bar style block not found");
  source = source.replace(
    styleNeedle,
    `                style={\n                  sameMonthPeer\n                    ? {\n                        fill: \"#73b99a\",\n                        opacity: 0.78,\n                        stroke: \"#146b49\",\n                        strokeWidth: 3,\n                      }\n                    : t2Excess\n                      ? { fill: \"#dc2626\" }\n                      : undefined\n                }`,
  );

  const oldTitle = `<h3>Evolución histórica del medidor</h3>`;
  const newTitle = `<h3 style={{display:"flex",alignItems:"baseline",gap:8,flexWrap:"wrap"}}>\n                <span>Evolución histórica del medidor</span>\n                <small style={{fontSize:11,fontWeight:700,color:"#78857f"}}>/ {(() => { const cp = dataForHeaderPeriod; return cp.name; })()}</small>\n              </h3>`;

  const sectionNeedle = `        <section className=\"invoice-analysis-panel\">\n          <div className=\"invoice-analysis-chart-head\">`;
  if (source.includes(sectionNeedle) && source.includes(oldTitle)) {
    const selectedPeriodNeedle = `  const selected =\n    history.find((i) => periodOf(i) === selectedPeriod) || invoice;`;
    if (source.includes(selectedPeriodNeedle) && !source.includes("dataForHeaderPeriod")) {
      source = source.replace(
        selectedPeriodNeedle,
        selectedPeriodNeedle + `\n  const selectedConsumptionPeriodForHeader = consumptionPeriod(selected);\n  const selectedConsumptionMonthForHeader = selectedConsumptionPeriodForHeader.slice(5, 7);\n  const selectedConsumptionYearForHeader = selectedConsumptionPeriodForHeader.slice(0, 4);\n  const dataForHeaderPeriod = {\n    name: \`${'${powerMonthNames[Number(selectedConsumptionMonthForHeader) - 1]?.toLowerCase() || "mes"}'} / ${'${selectedConsumptionMonthForHeader}'} / ${'${selectedConsumptionYearForHeader}'}\`,\n  };`,
      );
    }
    source = source.replace(oldTitle, newTitle);
  }

  writeFileSync(panelPath, source, "utf8");
}

console.log("Applied robust same-month peer highlight without out-of-scope variables.");
