import { readFileSync, writeFileSync } from "node:fs";
const p=new URL("../app/globals.css",import.meta.url);
let s=readFileSync(p,"utf8");
if(s.includes("POWER_TABLE_LAYOUT_V2")) process.exit(0);
s += `\n\n/* POWER_TABLE_LAYOUT_V2 */\n.improvement-power-table { overflow-x: auto; }\n.improvement-power-table > div {\n  grid-template-columns: minmax(90px,.55fr) minmax(120px,.7fr) minmax(125px,.75fr) minmax(145px,1fr) minmax(145px,1fr) minmax(145px,1fr) minmax(185px,1.1fr) !important;\n  min-width: 1180px;\n  align-items: center;\n}\n.improvement-power-head { align-items: center; }\n.improvement-power-table label { min-width: 0; }\n.improvement-power-table select,\n.improvement-power-table input { width: 100%; min-width: 0; }\n.power-application-period { display: block; }\n.power-application-period b { display: block; font-size: 12px; }\n.power-application-period small { display: block; margin-top: 3px; color: #7a8881; }\n`;
writeFileSync(p,s,"utf8");
console.log("Applied seven-column contracted-power table layout.");