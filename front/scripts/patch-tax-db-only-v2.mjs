import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/invoice-analysis-panel.tsx", import.meta.url);
let source = readFileSync(path, "utf8");
const marker = "// TAX_DB_ONLY_V2";
if (source.includes(marker)) process.exit(0);

source = source.replace(
  "  vat_amount?: number;\n  previous_debt_amount?: number;",
  "  vat_amount?: number;\n  vat_rate?: number;\n  vat_perception_amount?: number;\n  municipal_tax_amount?: number;\n  previous_debt_amount?: number;",
);

const calcPattern = /  const taxableBase = Number\([\s\S]*?  const taxTotal = taxRows\.reduce\(\(sum, row\) => sum \+ row\.amount, 0\);/;
if (!calcPattern.test(source)) {
  throw new Error("tax calculation block not found");
}

const calcReplacement = `  // TAX_DB_ONLY_V2\n  // Mostrar solamente impuestos guardados explícitamente en la factura.\n  // No inferir percepciones, tasas ni ajustes por diferencia contra el total.\n  const taxableBase = Number(selected.net_taxable || 0);\n  const vatAmount = Number(selected.vat_amount || 0);\n  const vatRate = Number(selected.vat_rate || 0);\n  const vatPerceptionAmount = Number(selected.vat_perception_amount || 0);\n  const municipalTaxAmount = Number(selected.municipal_tax_amount || 0);\n  const previousDebt = Number(selected.previous_debt_amount || 0);\n  const taxRows = [\n    ...(vatAmount !== 0\n      ? [{\n          name: "IVA",\n          source: "Registrado en base de datos",\n          base: taxableBase > 0 ? taxableBase : null,\n          rate: vatRate > 0 ? vatRate : null,\n          amount: vatAmount,\n        }]\n      : []),\n    ...(vatPerceptionAmount !== 0\n      ? [{\n          name: "Percepción de IVA",\n          source: "Registrado en base de datos",\n          base: taxableBase > 0 ? taxableBase : null,\n          rate: null,\n          amount: vatPerceptionAmount,\n        }]\n      : []),\n    ...(municipalTaxAmount !== 0\n      ? [{\n          name: "Tasa municipal",\n          source: "Registrado en base de datos",\n          base: null,\n          rate: null,\n          amount: municipalTaxAmount,\n        }]\n      : []),\n  ];\n  const taxTotal = taxRows.reduce((sum, row) => sum + row.amount, 0);`;
source = source.replace(calcPattern, calcReplacement);

// Quitar la fila de conciliación: no corresponde calcular diferencias.
source = source.replace(/\n\s*<tfoot>[\s\S]*?<\/tfoot>/, "");

// Quitar la leyenda histórica que explicaba la inferencia por diferencia.
source = source.replace(/\n\s*<p className="invoice-analysis-tax-note">\s*Los conceptos no discriminados se obtienen por diferencia para que\s*base, impuestos, ajustes y deuda coincidan con el total facturado\.\s*<\/p>/, "");

// Si no hay impuestos explícitos, mostrar un mensaje claro en vez de una tabla vacía.
const tableNeedle = `          <div className="invoice-analysis-table-wrap">\n            <table className="invoice-analysis-table">`;
const tableReplacement = `          {taxRows.length ? (\n          <div className="invoice-analysis-table-wrap">\n            <table className="invoice-analysis-table">`;
if (!source.includes(tableNeedle)) throw new Error("tax table start not found");
source = source.replace(tableNeedle, tableReplacement);

const sectionEndNeedle = `            </table>\n          </div>\n        </section>`;
const sectionEndReplacement = `            </table>\n          </div>\n          ) : (\n            <div style={{ padding: "18px 20px", color: "#64746d", fontSize: 13 }}>\n              Esta factura no tiene impuestos discriminados guardados en la base de datos.\n            </div>\n          )}\n        </section>`;
if (!source.includes(sectionEndNeedle)) throw new Error("tax table end not found");
source = source.replace(sectionEndNeedle, sectionEndReplacement);

writeFileSync(path, source, "utf8");
console.log("Applied DB-only taxes: no inferred reconciliation or difference calculations.");
