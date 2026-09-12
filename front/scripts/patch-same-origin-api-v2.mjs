import { readFileSync, writeFileSync } from "node:fs";

for (const relative of ["../app/page.tsx", "../app/invoice-analysis-panel.tsx", "../app/meter-location-editor.tsx"]) {
  const path = new URL(relative, import.meta.url);
  let source = readFileSync(path, "utf8");
  if (source.includes('const API = "/api/backend";') || source.includes('const API="/api/backend";')) continue;
  const next = source.replace(/const API\s*=\s*"[^"]+";/, 'const API = "/api/backend";');
  if (next === source) throw new Error("API constant not found in " + relative);
  writeFileSync(path, next, "utf8");
}

console.log("Applied same-origin API proxy constants.");
