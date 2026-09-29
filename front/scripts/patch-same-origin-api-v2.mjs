import { readFileSync, writeFileSync } from "node:fs";

// Run last: older build patches can restore absolute backend URLs.
for (const name of ["page", "invoice-analysis-panel", "meter-location-editor", "public-lighting-panel", "epen-optimization-panel", "meters-map"]) {
  const path = new URL(`../app/${name}.tsx`, import.meta.url);
  let source = readFileSync(path, "utf8").replace(/^\uFEFF/, "");
  if (!/const API\s*=/.test(source)) throw new Error("API constant not found in " + name);
  source = source.replace(/const API\s*=[^;]+;/, "const API = API_BASE;");
  const declaration = 'import { API_BASE } from "./lib/paths";';
  if (!source.includes(declaration)) {
    source = source.replace(/^("use client";|'use client';)/, `$1\n\n${declaration}`);
    if (!source.includes(declaration)) source = declaration + "\n" + source;
  }
  writeFileSync(path, source, "utf8");
}

console.log("Applied base-path-aware same-origin API proxy constants.");
