import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/page.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// DASHBOARD_PERF_V2";

if (source.includes(marker)) {
  console.log("Dashboard performance V2 already applied.");
  process.exit(0);
}

const formatterNeedle = `const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });`;
if (!source.includes(formatterNeedle)) {
  throw new Error("Could not locate dashboard formatter block.");
}
source = source.replace(
  formatterNeedle,
  formatterNeedle + `\n\n// DASHBOARD_PERF_V2\nconst changeControlsShortCache = new Map<string, { expiresAt: number; rows: MeterChangeControl[] }>();\nconst changeControlsInflight = new Map<string, Promise<MeterChangeControl[]>>();`,
);

const oldBlock = `  const loadChangeControls = useCallback(async (target?: string) => {\n    if (!target) {\n      setChangeControls([]);\n      return;\n    }\n    const { data, error } = await supabase\n      .from("meter_change_controls")\n      .select("*")\n      .eq("organization_id", target)\n      .order("effective_period", { ascending: true });\n    if (error) throw error;\n    setChangeControls((data || []) as MeterChangeControl[]);\n  }, []);`;

const newBlock = `  const loadChangeControls = useCallback(async (target?: string) => {\n    if (!target) {\n      setChangeControls([]);\n      return;\n    }\n\n    const cached = changeControlsShortCache.get(target);\n    if (cached && cached.expiresAt > Date.now()) {\n      setChangeControls(cached.rows);\n      return;\n    }\n\n    let pending = changeControlsInflight.get(target);\n    if (!pending) {\n      pending = supabase\n        .from("meter_change_controls")\n        .select("*")\n        .eq("organization_id", target)\n        .order("effective_period", { ascending: true })\n        .then(({ data, error }) => {\n          if (error) throw error;\n          const rows = (data || []) as MeterChangeControl[];\n          changeControlsShortCache.set(target, {\n            expiresAt: Date.now() + 1500,\n            rows,\n          });\n          return rows;\n        });\n      changeControlsInflight.set(target, pending);\n      pending.finally(() => changeControlsInflight.delete(target));\n    }\n\n    setChangeControls(await pending);\n  }, []);`;

if (!source.includes(oldBlock)) {
  throw new Error("Could not locate loadChangeControls block.");
}
source = source.replace(oldBlock, newBlock);

writeFileSync(path, source, "utf8");
console.log("Applied dashboard request deduplication for meter change controls.");
