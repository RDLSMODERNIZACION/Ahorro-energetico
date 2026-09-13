import { readFileSync, writeFileSync } from "node:fs";
const p = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let s = readFileSync(p, "utf8");
if (!s.includes("FINAL_HISTORY_SELECTION_V1")) {
  const yLine = "          const y = top + plotH - (graphValue / max) * plotH;";
  if (s.includes(yLine) && !s.includes("sameMonthPeerFinal")) {
    s = s.replace(yLine, yLine + "\n          const sameMonthPeerFinal = selectedPeriod !== d.billingPeriod && d.period.slice(5, 7) === (data.find((x) => x.billingPeriod === selectedPeriod)?.period.slice(5, 7) || \"\");");
  }
  const afterRect = "              </rect>\n              {(index % 3 === 0 || index === data.length - 1) && (";
  if (s.includes(afterRect)) {
    s = s.replace(afterRect, "              </rect>\n              {sameMonthPeerFinal && (\n                <rect\n                  x={x - 2}\n                  y={Math.max(top, y - 2)}\n                  width={bw + 4}\n                  height={Math.max(6, top + plotH - y + 4)}\n                  rx=\"7\"\n                  fill=\"none\"\n                  stroke=\"#146b49\"\n                  strokeWidth=\"4\"\n                  opacity=\"0.42\"\n                  pointerEvents=\"none\"\n                />\n              )}\n              {(index % 3 === 0 || index === data.length - 1) && (");
  }
  const title = "              <h3>Evolución histórica del medidor</h3>";
  if (s.includes(title)) {
    s = s.replace(title, "              <h3>Evolución histórica del medidor <small style={{fontSize:11,color:'#7b8982',fontWeight:600}}>/ {powerMonthNames[Number(consumptionPeriod(selected).slice(5,7))-1]?.toLowerCase()} / {consumptionPeriod(selected).slice(5,7)} / {consumptionPeriod(selected).slice(0,4)}</small></h3>");
  }
  s = s.replace("function InvoiceTrend({", "// FINAL_HISTORY_SELECTION_V1\nfunction InvoiceTrend({");
  writeFileSync(p, s, "utf8");
}
console.log("Applied final same-month bar outline and history period label.");
