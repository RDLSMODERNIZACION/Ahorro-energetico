import { readFileSync, writeFileSync } from "node:fs";
const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
if (source.includes("// DEFER_EPEN_V1")) process.exit(0);
const start = source.indexOf('        const epen = await api<EpenOptimizationResponse>(');
const endText = '        setEpenOptimization(epen?.meters || []);';
const end = source.indexOf(endText, start);
if (start < 0 || end < 0) throw new Error("EPEN block not found");
const replacement = [
'        // DEFER_EPEN_V1',
'        window.setTimeout(() => {',
'          api<EpenOptimizationResponse>("/api/organizations/" + target + "/epen-optimization?v=2", s)',
'            .then((epen) => setEpenOptimization(epen?.meters || []))',
'            .catch(() => undefined);',
'        }, 1800);',
].join("\n");
source = source.slice(0, start) + replacement + source.slice(end + endText.length);
writeFileSync(path, source, "utf8");
console.log("Deferred EPEN optimization request.");
