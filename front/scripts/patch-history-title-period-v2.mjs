import { readFileSync, writeFileSync } from "node:fs";
const p = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let s = readFileSync(p, "utf8");
if (!s.includes("HISTORY_TITLE_PERIOD_V2")) {
  const oldText = "              <h3>Evolución histórica del medidor</h3>";
  const newText = "              <h3>Evolución histórica del medidor <small style={{fontSize:11,color:'#7b8982',fontWeight:600}}>{/* HISTORY_TITLE_PERIOD_V2 */}/ {powerMonthNames[Number(consumptionPeriod(selected).slice(5,7))-1]?.toLowerCase()} / {consumptionPeriod(selected).slice(5,7)} / {consumptionPeriod(selected).slice(0,4)}</small></h3>";
  if (!s.includes(oldText)) throw new Error("history title not found");
  s = s.replace(oldText, newText);
  writeFileSync(p, s, "utf8");
}
console.log("Added selected period to history title.");
