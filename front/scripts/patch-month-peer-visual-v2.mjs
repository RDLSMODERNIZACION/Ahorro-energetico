import { readFileSync, writeFileSync } from "node:fs";
const p = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let s = readFileSync(p, "utf8");
if (!s.includes("SAME_MONTH_PEER_VISUAL_V2")) {
  s = s.replace(
    "          const y = top + plotH - (graphValue / max) * plotH;",
    "          const y = top + plotH - (graphValue / max) * plotH;\n          // SAME_MONTH_PEER_VISUAL_V2\n          const sameMonthPeer = selectedPeriod !== d.billingPeriod && d.period.slice(5, 7) === (data.find((x) => x.billingPeriod === selectedPeriod)?.period.slice(5, 7) || \"\");"
  );
  s = s.replace(
    "                style={t2Excess ? { fill: \"#dc2626\" } : undefined}",
    "                style={t2Excess ? { fill: \"#dc2626\", opacity: sameMonthPeer ? 0.7 : 1, stroke: sameMonthPeer ? \"#144b6b\" : undefined, strokeWidth: sameMonthPeer ? 3 : undefined } : sameMonthPeer ? { opacity: 0.7, stroke: \"#144b6b\", strokeWidth: 3 } : undefined}"
  );
  writeFileSync(p, s, "utf8");
}
console.log("Applied same-month peer visual V2.");
