import {readFileSync,writeFileSync} from "node:fs";
const p=new URL("../app/meter-change-control.tsx",import.meta.url);
let s=readFileSync(p,"utf8");
if(s.includes("AUDIT_CONSUMPTION_V4"))process.exit(0);
s=s.replace('const invoice = history.find((item) => consumptionPeriod(item) === period);','const invoice = history.find((item) => (String(item.period_end || "").slice(0,7) || consumptionPeriod(item)) === period); // AUDIT_CONSUMPTION_V4');
s=s.replace('const target = targetPowerFor(row, period);','const target = (()=>{const m=Number(period.slice(5,7)),y=Number(period.slice(0,4)),ey=Number(String(row.effective_period).slice(0,4)),em=Number(String(row.effective_period).slice(5,7));const ms=Array.isArray(row.details?.months)?row.details.months:[];const x=ms.find((z)=>Number(z.monthNumber)===m&&(Number(z.application_year||0)|| (m>=em?ey:ey+1))===y);return x?Number(x.effective_kw||0):0;})();');
writeFileSync(p,s,"utf8");
