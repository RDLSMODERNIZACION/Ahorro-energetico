import {readFileSync,writeFileSync} from "node:fs";
const p=new URL("../app/meter-change-control.tsx",import.meta.url);
let s=readFileSync(p,"utf8");
if(s.includes("AUDIT_CONSUMPTION_V5"))process.exit(0);
s=s.replaceAll('const invoice = history.find((item) => periodOf(item) === period);','const invoice = history.find((item) => String(item.period_end || "").slice(0,7) === period);');
s=s.replaceAll('const invoice = history.find((item) => consumptionPeriod(item) === period);','const invoice = history.find((item) => String(item.period_end || "").slice(0,7) === period);');
s=s.replaceAll('.filter((row) => row.effective_period.slice(0, 7) <= period)','.filter((row) => row.change_type === "contracted_power" ? targetPowerFor(row, period) > 0 : row.effective_period.slice(0, 7) <= period)');
s+='\n// AUDIT_CONSUMPTION_V5\n';
writeFileSync(p,s,"utf8");
