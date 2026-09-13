import { readFileSync, writeFileSync } from "node:fs";

const p = new URL("../app/meter-change-control.tsx", import.meta.url);
let s = readFileSync(p, "utf8");
if (s.includes("AUDIT_CONSUMPTION_V6")) process.exit(0);

s = s.replaceAll(
  'const invoice = history.find((item) => periodOf(item) === period);',
  'const invoice = history.find((item) => String(item.period_end || "").slice(0,7) === period);',
);
s = s.replaceAll(
  'const invoice = history.find((item) => consumptionPeriod(item) === period);',
  'const invoice = history.find((item) => String(item.period_end || "").slice(0,7) === period);',
);

const strictFilter = `.filter((row) => {
        if (row.change_type !== "contracted_power") {
          return row.effective_period.slice(0, 7) <= period;
        }
        const monthNumber = Number(period.slice(5, 7));
        const year = Number(period.slice(0, 4));
        const months = Array.isArray(row.details?.months)
          ? (row.details.months as Array<Record<string, unknown>>)
          : [];
        return months.some(
          (item) =>
            Number(item.monthNumber) === monthNumber &&
            Number(item.application_year || 0) === year &&
            Number(item.effective_kw || 0) > 0,
        );
      })`;

s = s.replaceAll(
  '.filter((row) => row.effective_period.slice(0, 7) <= period)',
  strictFilter,
);
s = s.replaceAll(
  '.filter((row) => row.effective_period.slice(0,7) <= period && (row.change_type !== "contracted_power" || targetPowerFor(row,period)>0))',
  strictFilter,
);
s = s.replaceAll(
  '.filter((row) => row.change_type === "contracted_power" ? targetPowerFor(row, period) > 0 : row.effective_period.slice(0, 7) <= period)',
  strictFilter,
);

s += '\n// AUDIT_CONSUMPTION_V6\n';
writeFileSync(p, s, "utf8");
console.log("Applied strict audit schedule matching by consumption month and application year.");
