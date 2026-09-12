import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// IMPROVEMENT_BUTTON_IN_PERIOD_V1";
if (source.includes(marker)) process.exit(0);

const periodNeedle = `          <div className="invoice-analysis-period">\n            <span>Mes de consumo</span>\n            <b>{consumptionPeriod(selected)}</b>\n            <small>Factura: {periodOf(selected)}</small>\n            <small>{selected.invoice_number || "S/D"}</small>\n          </div>`;

if (!source.includes(periodNeedle)) {
  throw new Error("invoice period card not found");
}

const periodReplacement = `          <div className="invoice-analysis-period">\n            <span>Mes de consumo</span>\n            <b>{consumptionPeriod(selected)}</b>\n            <small>Factura: {periodOf(selected)}</small>\n            <small>{selected.invoice_number || "S/D"}</small>\n            {/* IMPROVEMENT_BUTTON_IN_PERIOD_V1 */}\n            {organizationId && (\n              <>\n                <button\n                  type="button"\n                  onClick={() => setControlPageOpen(true)}\n                  style={{\n                    marginTop: 12,\n                    width: "100%",\n                    padding: "10px 12px",\n                    borderRadius: 10,\n                    border: "1px solid rgba(255,255,255,.14)",\n                    background: "#0b8f68",\n                    color: "#fff",\n                    fontWeight: 800,\n                    cursor: "pointer",\n                  }}\n                >\n                  Control de mejoras →\n                </button>\n                <small style={{ marginTop: 6, opacity: 0.78 }}>\n                  {changeControls.filter(\n                    (row) =>\n                      row.meter_id === selected.meter_id &&\n                      row.status !== "cancelled",\n                  ).length\n                    ? \`${"${changeControls.filter((row) => row.meter_id === selected.meter_id && row.status !== \"cancelled\").length}"} cambio(s) registrado(s)\`\n                    : "Sin cambios registrados"}\n                </small>\n              </>\n            )}\n          </div>`;

source = source.replace(periodNeedle, periodReplacement);

const launcherPattern = /\n\s*\{organizationId && \(\n\s*<MeterChangeControlPanel[\s\S]*?onOpenPage=\{\(\) => setControlPageOpen\(true\)\}[\s\S]*?\/>\n\s*\)\}\n/;
if (!launcherPattern.test(source)) {
  throw new Error("legacy improvement launcher block not found");
}
source = source.replace(launcherPattern, "\n");

writeFileSync(path, source, "utf8");
console.log("Moved improvement control launcher under consumption period card.");
