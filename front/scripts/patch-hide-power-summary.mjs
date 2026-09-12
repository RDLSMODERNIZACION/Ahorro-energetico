import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// HIDE_POWER_SUMMARY_V1";
if (source.includes(marker)) process.exit(0);

const startNeedle = '        {powerCurve.hasData && (\n          <div className={styles.powerCurveSummary}>';
const endNeedle = '\n\n        <div className="invoice-analysis-kpis">';
const start = source.indexOf(startNeedle);
const end = source.indexOf(endNeedle, start);

if (start < 0 || end < 0) {
  throw new Error("power curve summary block not found");
}

source =
  source.slice(0, start) +
  '        {/* HIDE_POWER_SUMMARY_V1 */}' +
  source.slice(end);

writeFileSync(path, source, "utf8");
console.log("Hidden top power summary strip (current/proposal/saving/excel).");
