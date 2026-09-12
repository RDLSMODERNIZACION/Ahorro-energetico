import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
if (source.includes("// DASHBOARD_BOOTSTRAP_V1")) process.exit(0);

const startText = '        const [m, i, o] = await Promise.all([';
const endText = '        setOpportunities(o);';
const start = source.indexOf(startText);
const end = source.indexOf(endText, start);
if (start < 0 || end < 0) throw new Error("startup request block not found");

const replacement = [
  '        // DASHBOARD_BOOTSTRAP_V1',
  '        const bootstrap = await api<{ period: string | null; meters: Meter[]; invoices: Invoice[] }>(',
  '          `/api/organizations/${target}/dashboard-bootstrap`,',
  '          s,',
  '        );',
  '        const m = bootstrap.meters || [];',
  '        const i = bootstrap.invoices || [];',
  '        const o: Opportunity[] = [];',
  '        setMeters(m);',
  '        setInvoices(i);',
  '        setOpportunities(o);',
].join("\n");

source = source.slice(0, start) + replacement + source.slice(end + endText.length);
writeFileSync(path, source, "utf8");
console.log("Applied single-request dashboard bootstrap.");
