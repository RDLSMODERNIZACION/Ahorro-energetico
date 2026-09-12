import { readFileSync, writeFileSync } from "node:fs";
const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
if (source.includes("// LAZY_EPEN_TAB_V2")) process.exit(0);
const startText = '        const epen = await api<EpenOptimizationResponse>(';
const endText = '        setEpenOptimization(epen?.meters || []);';
const start = source.indexOf(startText);
const end = source.indexOf(endText, start);
if (start < 0 || end < 0) throw new Error("EPEN startup block not found");
source = source.slice(0, start) + '        // LAZY_EPEN_TAB_V2\n' + source.slice(end + endText.length);
const anchor = '  async function login(e: FormEvent) {';
if (!source.includes(anchor)) throw new Error("login anchor not found");
const effect = [
  '  useEffect(() => {',
  '    if (!session || !orgId) return;',
  '    if (tab !== "invoices" && tab !== "framing") return;',
  '    if (epenOptimization.length) return;',
  '    api<EpenOptimizationResponse>(`/api/organizations/${orgId}/epen-optimization?v=2`, session)',
  '      .then((epen) => setEpenOptimization(epen?.meters || []))',
  '      .catch(() => undefined);',
  '  }, [session, orgId, tab, epenOptimization.length]);',
  '',
].join("\n");
source = source.replace(anchor, effect + anchor);
writeFileSync(path, source, "utf8");
console.log("Applied tab-based lazy EPEN loading.");
