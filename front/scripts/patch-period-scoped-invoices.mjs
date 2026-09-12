import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// PERIOD_SCOPED_INVOICES_V1";
if (source.includes(marker)) process.exit(0);

const initialNeedle = '`/api/organizations/${target}/invoices?limit=5000&summary=true`';
if (!source.includes(initialNeedle)) throw new Error("summary invoice startup URL not found");
source = source.replace(
  initialNeedle,
  '`/api/organizations/${target}/invoices?latest=true&limit=500&summary=true`',
);

const refNeedle = '  const loadedDataKey = useRef("");';
if (!source.includes(refNeedle)) throw new Error("loadedDataKey ref not found");
source = source.replace(
  refNeedle,
  refNeedle + '\n  // PERIOD_SCOPED_INVOICES_V1\n  const loadedInvoicePeriods = useRef<Set<string>>(new Set());\n  const invoicePeriodInflight = useRef<Set<string>>(new Set());',
);

const setInvoicesNeedle = '        setInvoices(i);';
if (!source.includes(setInvoicesNeedle)) throw new Error("initial setInvoices not found");
source = source.replace(
  setInvoicesNeedle,
  setInvoicesNeedle + '\n        for (const row of i) loadedInvoicePeriods.current.add((row.billing_period || row.period_start).slice(0, 7));',
);

const periodsNeedle = '  const periods = [...new Set(invoices.map(invoiceMonth))].sort().reverse();\n  const years = [...new Set(periods.map((x) => x.slice(0, 4)))];';
if (!source.includes(periodsNeedle)) throw new Error("periods block not found");
const periodsReplacement = `  const loadedPeriods = [...new Set(invoices.map(invoiceMonth))].sort().reverse();\n  const latestKnownPeriod = loadedPeriods[0] || "";\n  const periods = useMemo(() => {\n    if (!latestKnownPeriod) return [] as string[];\n    const [year, month] = latestKnownPeriod.split("-").map(Number);\n    return Array.from({ length: 24 }, (_, index) => {\n      const date = new Date(Date.UTC(year, month - 1 - index, 1));\n      return \`${"${date.getUTCFullYear()}"}-\${String(date.getUTCMonth() + 1).padStart(2, "0")}\`;\n    });\n  }, [latestKnownPeriod]);\n  const years = [...new Set(periods.map((x) => x.slice(0, 4)))];`;
source = source.replace(periodsNeedle, periodsReplacement);

const loadEffectNeedle = `  useEffect(() => {\n    if (!session) return;\n    const key = orgId ? \`${"${session.user.id}:${orgId}"}\` : "";\n    if (key && loadedDataKey.current === key) return;\n    load(session, orgId);\n  }, [session, orgId, load]);`;
if (!source.includes(loadEffectNeedle)) throw new Error("main load effect not found");
const periodEffect = `\n\n  useEffect(() => {\n    if (!session || !orgId || yearFilter === "all" || monthFilter === "all") return;\n    const period = \`${"${yearFilter}-${monthFilter}"}\`;\n    if (loadedInvoicePeriods.current.has(period) || invoicePeriodInflight.current.has(period)) return;\n\n    invoicePeriodInflight.current.add(period);\n    api<Invoice[]>(\n      \`/api/organizations/\${orgId}/invoices?period=\${period}&limit=500&summary=true\`,\n      session,\n    )\n      .then((rows) => {\n        loadedInvoicePeriods.current.add(period);\n        if (!rows.length) return;\n        setInvoices((current) => {\n          const byId = new Map(current.map((row) => [row.id, row]));\n          for (const row of rows) byId.set(row.id, row);\n          return [...byId.values()];\n        });\n      })\n      .catch(() => {\n        loadedInvoicePeriods.current.add(period);\n      })\n      .finally(() => invoicePeriodInflight.current.delete(period));\n  }, [session, orgId, yearFilter, monthFilter]);`;
source = source.replace(loadEffectNeedle, loadEffectNeedle + periodEffect);

const openByIdNeedle = `  const openMeterById = (meterId?: string) => {\n    if (!meterId) return;\n    const i = [...invoices]\n      .filter((x) => x.meter_id === meterId)\n      .sort((a, b) => invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];\n    if (i) openMeter(i);\n  };`;
if (!source.includes(openByIdNeedle)) throw new Error("openMeterById block not found");
const openByIdReplacement = `  const openMeterById = async (meterId?: string) => {\n    if (!meterId) return;\n    const local = [...invoices]\n      .filter((x) => x.meter_id === meterId)\n      .sort((a, b) => invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];\n    if (local) {\n      await openMeter(local);\n      return;\n    }\n    if (!session || !orgId) return;\n    try {\n      const history = await api<Invoice[]>(\n        \`/api/organizations/\${orgId}/invoices?meter_id=\${meterId}&limit=24\`,\n        session,\n      );\n      if (!history.length) return;\n      setSelectedHistory(history);\n      await openMeter(history[0]);\n    } catch (error) {\n      setToast(error instanceof Error ? error.message : "No se pudo cargar el historial del medidor");\n    }\n  };`;
source = source.replace(openByIdNeedle, openByIdReplacement);

writeFileSync(path, source, "utf8");
console.log("Applied latest-period startup and on-demand monthly invoice loading.");
