import { readFileSync, writeFileSync } from "node:fs";

const documentsPath = new URL("../app/meter-documents.tsx", import.meta.url);
let documents = readFileSync(documentsPath, "utf8");
const marker = "// METER_DOCUMENTS_CLOSE_V1";

if (!documents.includes(marker)) {
  documents = documents.replace(
    "  onPeriod,\n}: {",
    "  onPeriod,\n  onClose,\n}: {",
  );
  documents = documents.replace(
    "  onPeriod?: (period: string) => void;\n}) {",
    "  onPeriod?: (period: string) => void;\n  onClose?: () => void;\n}) {",
  );

  const headerNeedle = `      <div\n        style={{\n          display: \"grid\",\n          gridTemplateColumns: \"48px 1fr 48px\",\n          alignItems: \"center\",\n          gap: 14,\n          marginBottom: 20,\n        }}\n      >`;
  const headerReplacement = `      {/* METER_DOCUMENTS_CLOSE_V1 */}\n      <div style={{ display: \"flex\", justifyContent: \"flex-end\", marginBottom: 10 }}>\n        {onClose && (\n          <button\n            type=\"button\"\n            onClick={onClose}\n            style={{\n              padding: \"8px 12px\",\n              borderRadius: 10,\n              border: \"1px solid #d5e1db\",\n              background: \"#f7faf8\",\n              color: \"#42554c\",\n              fontWeight: 800,\n              cursor: \"pointer\",\n            }}\n          >\n            Guardar y cerrar ↑\n          </button>\n        )}\n      </div>\n      <div\n        style={{\n          display: \"grid\",\n          gridTemplateColumns: \"48px 1fr 48px\",\n          alignItems: \"center\",\n          gap: 14,\n          marginBottom: 20,\n        }}\n      >`;

  if (!documents.includes(headerNeedle)) {
    throw new Error("meter documents header not found");
  }
  documents = documents.replace(headerNeedle, headerReplacement);
  writeFileSync(documentsPath, documents, "utf8");
}

const panelPath = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let panel = readFileSync(panelPath, "utf8");
if (!panel.includes("onClose={() => setDocumentsOpen(false)}")) {
  const needle = `            controls={changeControls}\n            onPeriod={setSelectedPeriod}\n          />`;
  const replacement = `            controls={changeControls}\n            onPeriod={setSelectedPeriod}\n            onClose={() => setDocumentsOpen(false)}\n          />`;
  if (!panel.includes(needle)) throw new Error("open MeterDocuments block not found");
  panel = panel.replace(needle, replacement);
  writeFileSync(panelPath, panel, "utf8");
}

console.log("Added Guardar y cerrar control to meter documents panel.");
