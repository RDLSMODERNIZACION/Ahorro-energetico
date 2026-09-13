import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// RESTORE_CHANGE_CONTROLS_LOAD_V1";
if (source.includes(marker)) process.exit(0);

const needle = `        setMeters(m);\n        setInvoices(i);\n        setOpportunities(o);`;
if (!source.includes(needle)) throw new Error("dashboard bootstrap assignment block not found");

source = source.replace(
  needle,
  `${needle}\n        // RESTORE_CHANGE_CONTROLS_LOAD_V1\n        await loadChangeControls(target);`,
);

writeFileSync(path, source, "utf8");
console.log("Restored meter change controls loading after dashboard bootstrap.");
