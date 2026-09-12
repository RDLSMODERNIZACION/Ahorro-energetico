import { readFileSync, writeFileSync } from "node:fs";
const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
if (source.includes("// LAZY_TARIFF_DATA_V1")) process.exit(0);
const refs = '  const invoiceFiltersInitialized = useRef(false);\n  const loadedDataKey = useRef("");';
if (!source.includes(refs)) throw new Error("refs anchor not found");
source = source.replace(refs, refs + '\n  // LAZY_TARIFF_DATA_V1\n  const tariffDataLoaded = useRef("");');
const anchor = '  async function login(e: FormEvent) {';
if (!source.includes(anchor)) throw new Error("login anchor not found");
const effect = [
'  useEffect(() => {',
'    if (!session || !orgId) return;',
'    const needed = tab === "invoices" || tab === "framing" || tab === "tariffs" || tab === "ai";',
'    if (!needed || tariffDataLoaded.current === orgId) return;',
'    tariffDataLoaded.current = orgId;',
'    Promise.all([',
'      api<TariffAssessment[]>("/api/organizations/" + orgId + "/tariff-assessments?v=14", session).catch(() => []),',
'      api<TariffSavingResponse>("/api/organizations/" + orgId + "/tariff-savings?v=1", session).catch(() => null),',
'    ]).then(([frames, tariffResult]) => {',
'      setAssessments(frames);',
'      setTariffSavings(tariffResult?.candidates || []);',
'    }).catch(() => { tariffDataLoaded.current = ""; });',
'  }, [session, orgId, tab]);',
'',
].join("\n");
source = source.replace(anchor, effect + anchor);
writeFileSync(path, source, "utf8");
console.log("Lazy tariff data loading applied.");
