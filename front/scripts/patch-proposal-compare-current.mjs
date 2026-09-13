import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// PROPOSAL_COMPARE_CURRENT_V1";
if (source.includes(marker)) {
  console.log("Proposal/current comparison patch already applied.");
  process.exit(0);
}

const oldMax = `  const max =\n    Math.max(\n      1,\n      ...data.map((d) => d.value),\n      ...(metric === \"demand\"\n        ? data.map((d) =>\n            powerLine === \"proposal\" ? d.proposed : d.contracted,\n          )\n        : []),\n    ) * 1.08;`;
const newMax = `  // PROPOSAL_COMPARE_CURRENT_V1\n  // Mantener exactamente la misma escala entre Actual y Propuesta.\n  // En demanda, el dominio siempre contempla demanda registrada, contratada actual y propuesta.\n  const max =\n    Math.max(\n      1,\n      ...data.map((d) => d.value),\n      ...(metric === \"demand\" ? data.map((d) => d.contracted) : []),\n      ...(metric === \"demand\" ? data.map((d) => d.proposed) : []),\n    ) * 1.08;`;
if (!source.includes(oldMax)) throw new Error("InvoiceTrend max scale block not found");
source = source.replace(oldMax, newMax);

const oldCurrentCondition = `        {metric === \"demand\" &&\n          powerLine === \"current\" &&\n          data.map((d, index) =>`;
const newCurrentCondition = `        {metric === \"demand\" &&\n          data.map((d, index) =>`;
if (!source.includes(oldCurrentCondition)) throw new Error("current contracted line condition not found");
source = source.replace(oldCurrentCondition, newCurrentCondition);

const proposalLegendNeedle = `          ) : (\n            <>\n              <span>\n                <i className=\"proposal\" />\n                Contratada propuesta óptima · mes seleccionado marcado\n              </span>\n              <span>\n                <i style={{ background: \"#dc2626\" }} />\n                T2 con EXC proyectado bajo la propuesta\n              </span>\n            </>\n          )}`;
const proposalLegendReplacement = `          ) : (\n            <>\n              <span>\n                <i className=\"current\" />\n                Contratada actual\n              </span>\n              <span>\n                <i className=\"proposal\" />\n                Contratada propuesta óptima · mes seleccionado marcado\n              </span>\n              <span>\n                <i style={{ background: \"#dc2626\" }} />\n                T2 con EXC proyectado bajo la propuesta\n              </span>\n            </>\n          )}`;
if (!source.includes(proposalLegendNeedle)) throw new Error("proposal legend block not found after T2 excess patch");
source = source.replace(proposalLegendNeedle, proposalLegendReplacement);

writeFileSync(path, source, "utf8");
console.log("Proposal view now shows current contracted line and keeps a fixed comparison scale.");
