import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// INVOICE_SUMMARY_LAZY_DETAIL_V1";
if (source.includes(marker)) process.exit(0);

source = source.replace(
  '`/api/organizations/${target}/invoices?limit=5000`',
  '`/api/organizations/${target}/invoices?limit=5000&summary=true`',
);

const selectedNeedle = '    [selectedInvoice, setSelectedInvoice] = useState<Invoice | null>(null),';
if (!source.includes(selectedNeedle)) throw new Error("selectedInvoice state not found");
source = source.replace(
  selectedNeedle,
  selectedNeedle + '\n    // INVOICE_SUMMARY_LAZY_DETAIL_V1\n    [selectedHistory, setSelectedHistory] = useState<Invoice[]>([]),',
);

const openNeedle = `  const openMeter = (i: Invoice) => {\n    setSelectedInvoice(i);\n    setSelectedMeter(i.meter_id);\n    setTab("invoices");\n  };`;
if (!source.includes(openNeedle)) throw new Error("openMeter block not found");
const openReplacement = `  async function openMeter(i: Invoice) {\n    setSelectedInvoice(i);\n    setSelectedHistory(invoices.filter((row) => row.meter_id === i.meter_id));\n    setSelectedMeter(i.meter_id);\n    setInvoiceSubTab("received");\n    setTab("invoices");\n    if (!session || !orgId) return;\n    try {\n      const [detail, history] = await Promise.all([\n        api<Invoice>(\`/api/invoices/\${i.id}\`, session),\n        api<Invoice[]>(\`/api/organizations/\${orgId}/invoices?meter_id=\${i.meter_id}&limit=24\`, session),\n      ]);\n      setSelectedInvoice(detail);\n      setSelectedHistory(history);\n    } catch (error) {\n      setToast(error instanceof Error ? error.message : "No se pudo cargar el detalle de la factura");\n    }\n  }`;
source = source.replace(openNeedle, openReplacement);

const historyNeedle = `history={invoices.filter(\n                      (x) => x.meter_id === selectedInvoice.meter_id,\n                    )}`;
const historyReplacement = `history={\n                      selectedHistory.length\n                        ? selectedHistory\n                        : invoices.filter(\n                            (x) => x.meter_id === selectedInvoice.meter_id,\n                          )\n                    }`;
let historyCount = 0;
while (source.includes(historyNeedle)) {
  source = source.replace(historyNeedle, historyReplacement);
  historyCount++;
}
if (!historyCount) throw new Error("analysis history props not found");

const closeNeedle = 'onClose={() => setSelectedInvoice(null)}';
const closeReplacement = 'onClose={() => { setSelectedInvoice(null); setSelectedHistory([]); }}';
source = source.split(closeNeedle).join(closeReplacement);

writeFileSync(path, source, "utf8");
console.log("Applied compact invoice summary load with lazy full invoice/history detail.");
