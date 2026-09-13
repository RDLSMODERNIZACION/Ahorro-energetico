import { readFileSync, writeFileSync } from "node:fs";
const p = new URL("./build-vercel.mjs", import.meta.url);
let s = readFileSync(p, "utf8");
if (!s.includes("patch-audit-consumption-v4.mjs")) {
  s = s.replace("patch-audit-consumption-month.mjs\",", "patch-audit-consumption-month.mjs\",\n  \"patch-audit-consumption-v4.mjs\",");
  writeFileSync(p, s, "utf8");
}
await import("./build-vercel.mjs");
