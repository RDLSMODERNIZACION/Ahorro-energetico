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
if (calcPattern.test(source)) {
  const calcReplacement = `  // TAX_DB_ONLY_V2\n  // Mostrar solamente impuestos guardados explícitamente en la factura.\n  // No inferir percepciones, tasas ni ajustes por diferencia contra el total.\n  const taxableBase = Number(selected.net_taxable || 0);\n  const vatAmount = Number(selected.vat_amount || 0);\n  const vatRate = Number(selected.vat_rate || 0);\n  const vatPerceptionAmount = Number(selected.vat_perception_amount || 0);\n  const municipalTaxAmount = Number(selected.municipal_tax_amount || 0);\n  const previousDebt = Number(selected.previous_debt_amount || 0);\n  const taxRows = [\n    ...(vatAmount !== 0\n      ? [{\n          name: "IVA",\n          source: "Registrado en base de datos",\n          base: taxableBase > 0 ? taxableBase : null,\n          rate: vatRate > 0 ? vatRate : null,\n          amount: vatAmount,\n        }]\n      : []),\n    ...(vatPerceptionAmount !== 0\n      ? [{\n          name: "Percepción de IVA",\n          source: "Registrado en base de datos",\n          base: null,\n          rate: null,\n          amount: vatPerceptionAmount,\n        }]\n      : []),\n    ...(municipalTaxAmount !== 0\n      ? [{\n          name: "Tasa municipal",\n          source: "Registrado en base de datos",\n          base: null,\n          rate: null,\n          amount: municipalTaxAmount,\n        }]\n      : []),\n  ];\n  const taxTotal = taxRows.reduce((sum, row) => sum + row.amount, 0);`;
  source = source.replace(calcPattern, calcReplacement);
}

// Quitar cualquier pie de conciliación del bloque de impuestos.
source = source.replace(/\n\s*<tfoot>[\s\S]*?<\/tfoot>/, "");

// Quitar definitivamente la leyenda de inferencia por diferencia.
source = source.replace(/\n\s*<p className="invoice-analysis-tax-note">\s*Los conceptos no discriminados se obtienen por diferencia para que\s*base, impuestos, ajustes y deuda coincidan con el total facturado\.\s*<\/p>/, "");

// Reemplazar cualquier origen antiguo que indicaba conciliación/inferencia.
source = source.replaceAll("Identificada por conciliación con el total", "Registrado en base de datos");
source = source.replaceAll("Diferencia conciliada con el total de la factura", "Registrado en base de datos");

if (!source.includes(marker)) {
  // Si el bloque de cálculo ya había sido modificado por otro parche, dejar una marca segura.
  source = source.replace(
    '"use client";',
    '"use client";\n// TAX_DB_ONLY_V2',
  );
}

writeFileSync(path, source, "utf8");
console.log("Applied DB-only taxes: stored values only, no reconciliation or inferred differences.");
