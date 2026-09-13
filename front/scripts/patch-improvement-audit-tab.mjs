import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/meter-change-control.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// IMPROVEMENT_AUDIT_TAB_V1";
if (source.includes(marker)) process.exit(0);

source = source.replace(
  '  const [workspace, setWorkspace] = useState<"register" | "history">("history"),',
  '  // IMPROVEMENT_AUDIT_TAB_V1\n  const [workspace, setWorkspace] = useState<"register" | "history" | "audit">("history"),',
);

const tabNeedle = `              <button\n                className={workspace === "history" ? "active" : ""}\n                onClick={() => setWorkspace("history")}\n              >\n                Historial y seguimiento ({controls.length})\n              </button>`;
const tabReplacement = `${tabNeedle}\n              <button\n                className={workspace === "audit" ? "active" : ""}\n                onClick={() => setWorkspace("audit")}\n              >\n                Auditoría y control\n              </button>`;
if (!source.includes(tabNeedle)) throw new Error("history tab not found");
source = source.replace(tabNeedle, tabReplacement);

source = source.replace(
  '{workspace === "history" && (',
  '{(workspace === "history" || workspace === "audit") && (',
);

source = source.replace(
  '<div className="improvement-history-title">',
  '<div className="improvement-history-title" style={{ display: workspace === "history" ? undefined : "none" }}>',
);
source = source.replace(
  '{!controls.length && (',
  '{workspace === "history" && !controls.length && (',
);
source = source.replace(
  '<div className="improvement-history-list">',
  '<div className="improvement-history-list" style={{ display: workspace === "history" ? undefined : "none" }}>',
);

const auditCondition = '{!!auditControls.length && (';
if (!source.includes(auditCondition)) throw new Error("audit table condition not found");
source = source.replace(auditCondition, '{workspace === "audit" && !!auditControls.length && (');

const auditInsertPoint = '                {workspace === "audit" && !!auditControls.length && (';
source = source.replace(
  auditInsertPoint,
  `                {workspace === "audit" && !auditControls.length && (\n                  <div className="improvement-history-empty">\n                    <b>Sin mejoras vigentes para auditar</b>\n                    <span>Registrá una mejora de potencia, tarifa o factor de potencia para iniciar el control mensual.</span>\n                  </div>\n                )}\n${auditInsertPoint}`,
);

writeFileSync(path, source, "utf8");
console.log("Separated Historial y seguimiento from Auditoría y control.");
