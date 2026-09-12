import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// INVOICE_SUMMARY_LAZY_DETAIL_V2";
if (source.includes(marker)) process.exit(0);

source = source.replace(
  '`/api/organizations/${target}/invoices?limit=5000`',
  '`/api/organizations/${target}/invoices?latest=true&limit=500&summary=true`',
);

const selectedNeedle = '    [selectedInvoice, setSelectedInvoice] = useState<Invoice | null>(null),';
if (!source.includes(selectedNeedle)) throw new Error("selectedInvoice state not found");
source = source.replace(
  selectedNeedle,
  selectedNeedle + '\n    // INVOICE_SUMMARY_LAZY_DETAIL_V2\n    [selectedHistory, setSelectedHistory] = useState<Invoice[]>([]),',
);

const refNeedle = '  const loadedDataKey = useRef("");';
if (!source.includes(refNeedle)) throw new Error("loadedDataKey ref not found");
source = source.replace(
  refNeedle,
  refNeedle + '\n  const loadedInvoicePeriods = useRef<Set<string>>(new Set());\n  const invoicePeriodInflight = useRef<Set<string>>(new Set());',
);

const setInvoicesNeedle = '        setInvoices(i);';
if (!source.includes(setInvoicesNeedle)) throw new Error("initial setInvoices not found");
source = source.replace(
  setInvoicesNeedle,
  setInvoicesNeedle + '\n        for (const row of i) loadedInvoicePeriods.current.add((row.billing_period || row.period_start).slice(0, 7));',
);

const openNeedle = `  const openMeter = (i: Invoice) => {\n    setSelectedInvoice(i);\n    setSelectedMeter(i.meter_id);\n    setTab("invoices");\n  };`;
if (!source.includes(openNeedle)) throw new Error("openMeter block not found");
const openReplacement = `  async function openMeter(i: Invoice) {\n    setSelectedInvoice(i);\n    setSelectedHistory(invoices.filter((row) => row.meter_id === i.meter_id));\n    setSelectedMeter(i.meter_id);\n    setInvoiceSubTab("received");\n    setTab("invoices");\n    if (!session || !orgId) return;\n    try {\n      const [detail, history] = await Promise.all([\n        api<Invoice>(\`/api/invoices/\${i.id}\`, session),\n        api<Invoice[]>(\`/api/organizations/\${orgId}/invoices?meter_id=\${i.meter_id}&limit=24\`, session),\n      ]);\n      setSelectedInvoice(detail);\n      setSelectedHistory(history);\n    } catch (error) {\n      setToast(error instanceof Error ? error.message : "No se pudo cargar el detalle de la factura");\n    }\n  }`;
source = source.replace(openNeedle, openReplacement);

const periodsNeedle = '  const periods = [...new Set(invoices.map(invoiceMonth))].sort().reverse();\n  const years = [...new Set(periods.map((x) => x.slice(0, 4)))];';
if (!source.includes(periodsNeedle)) throw new Error("periods block not found");
source = source.replace(
  periodsNeedle,
  `  const loadedPeriods = [...new Set(invoices.map(invoiceMonth))].sort().reverse();\n  const latestKnownPeriod = loadedPeriods[0] || "";\n  const periods = useMemo(() => {\n    if (!latestKnownPeriod) return [] as string[];\n    const [year, month] = latestKnownPeriod.split("-").map(Number);\n    return Array.from({ length: 24 }, (_, index) => {\n      const date = new Date(Date.UTC(year, month - 1 - index, 1));\n      return String(date.getUTCFullYear()) + "-" + String(date.getUTCMonth() + 1).padStart(2, "0");\n    });\n  }, [latestKnownPeriod]);\n  const years = [...new Set(periods.map((x) => x.slice(0, 4)))];`,
);

const loadEffectNeedle = `  useEffect(() => {\n    if (!session) return;\n    const key = orgId ? \`\${session.user.id}:\${orgId}\` : "";\n    if (key && loadedDataKey.current === key) return;\n    load(session, orgId);\n  }, [session, orgId, load]);`;
if (!source.includes(loadEffectNeedle)) throw new Error("main load effect not found");
source = source.replace(
  loadEffectNeedle,
  loadEffectNeedle + `\n\n  useEffect(() => {\n    if (!session || !orgId || yearFilter === "all" || monthFilter === "all") return;\n    const period = yearFilter + "-" + monthFilter;\n    if (loadedInvoicePeriods.current.has(period) || invoicePeriodInflight.current.has(period)) return;\n    invoicePeriodInflight.current.add(period);\n    api<Invoice[]>(\`/api/organizations/\${orgId}/invoices?period=\${period}&limit=500&summary=true\`, session)\n      .then((rows) => {\n        loadedInvoicePeriods.current.add(period);\n        if (!rows.length) return;\n        setInvoices((current) => {\n          const byId = new Map(current.map((row) => [row.id, row]));\n          for (const row of rows) byId.set(row.id, row);\n          return [...byId.values()];\n        });\n      })\n      .catch(() => loadedInvoicePeriods.current.add(period))\n      .finally(() => invoicePeriodInflight.current.delete(period));\n  }, [session, orgId, yearFilter, monthFilter]);`,
);

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
console.log("Applied latest-period startup, monthly on-demand loading and lazy invoice history detail.");
