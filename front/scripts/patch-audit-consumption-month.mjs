import { readFileSync, writeFileSync } from "node:fs";

const p = new URL("../app/meter-change-control.tsx", import.meta.url);
let s = readFileSync(p, "utf8");
if (s.includes("AUDIT_CONSUMPTION_MONTH_V2")) process.exit(0);

s = s.replace(
  'import { supabase } from "./lib/supabase";',
  'import { supabase } from "./lib/supabase";\nimport { consumptionPeriod } from "./lib/power-history";',
);

s = s.replace(
  '    const invoice = history.find((item) => periodOf(item) === period);',
  '    // AUDIT_CONSUMPTION_MONTH_V2\n    const invoice = history.find((item) => consumptionPeriod(item) === period);',
);

s = s.replace(
  'return { period, row, invoice, expected, received, result, detail };',
  'return { period, billingPeriod: invoice ? periodOf(invoice) : "", row, invoice, expected, received, result, detail };',
);

s = s.replace(
  '["Período", "Mejora controlada", "Esperado", "Recibido", "Resultado"]',
  '["Consumo", "Facturación", "Mejora controlada", "Esperado", "Recibido", "Resultado"]',
);

s = s.replace(
  '<td style={{ padding: "13px 14px", fontWeight: 800, whiteSpace: "nowrap" }}>{item.period}</td>\n                                <td style={{ padding: "13px 14px" }}>',
  '<td style={{ padding: "13px 14px", fontWeight: 800, whiteSpace: "nowrap" }}>{item.period}</td>\n                                <td style={{ padding: "13px 14px", fontWeight: 800, whiteSpace: "nowrap" }}>{item.billingPeriod || "Pendiente"}</td>\n                                <td style={{ padding: "13px 14px" }}>',
);

writeFileSync(p, s, "utf8");
console.log("Audit aligned to consumption month without out-of-scope billingPeriod.");
