import fs from "node:fs";
import path from "node:path";

const root = process.env.SITES_PROJECT_ROOT || path.resolve(process.cwd());
const file = path.join(root, "app", "page.tsx");
let source = fs.readFileSync(file, "utf8");

const before = `                <td>\n                  <b>{number.format(x.contracted)} kW</b>\n                  <small className={x.excess > 0 ? "danger" : "ok"}>\n                    {x.excess > 0\n                      ? \`${'${number.format(x.excess)}'} kW de más\`\n                      : "Sin potencia sobrante"}\n                  </small>\n                </td>`;

const t1OnlyAfter = `                <td>\n                  {String(\n                    i.current_tariff_code || i.meters?.current_tariff_code || "",\n                  )\n                    .toUpperCase()\n                    .startsWith("T1") ? (\n                    <>\n                      <b>—</b>\n                      <small className="muted">No aplica en tarifa T1</small>\n                    </>\n                  ) : (\n                    <>\n                      <b>{number.format(x.contracted)} kW</b>\n                      <small className={x.excess > 0 ? "danger" : "ok"}>\n                        {x.excess > 0\n                          ? \`${'${number.format(x.excess)}'} kW de más\`\n                          : "Sin potencia sobrante"}\n                      </small>\n                    </>\n                  )}\n                </td>`;

const after = `                <td>\n                  {String(\n                    i.current_tariff_code || i.meters?.current_tariff_code || "",\n                  )\n                    .toUpperCase()\n                    .startsWith("T1") ? (\n                    <>\n                      <b>—</b>\n                      <small className="muted">No aplica en tarifa T1</small>\n                    </>\n                  ) : String(\n                      i.current_tariff_code || i.meters?.current_tariff_code || "",\n                    )\n                      .toUpperCase()\n                      .startsWith("T2") &&\n                    Math.max(\n                      0,\n                      ...(i.invoice_lines || [])\n                        .filter(\n                          (line) =>\n                            String(line.concept_code || "").toUpperCase() === "EXC",\n                        )\n                        .map((line) => Number(line.quantity || 0)),\n                      Math.max(0, x.demand - x.contracted),\n                    ) > 0 ? (\n                    <>\n                      <b>{number.format(x.contracted)} kW</b>\n                      <small className="danger">\n                        Exceso: {number.format(\n                          Math.max(\n                            0,\n                            ...(i.invoice_lines || [])\n                              .filter(\n                                (line) =>\n                                  String(line.concept_code || "").toUpperCase() ===\n                                  "EXC",\n                              )\n                              .map((line) => Number(line.quantity || 0)),\n                            Math.max(0, x.demand - x.contracted),\n                          ),\n                        )} kW\n                      </small>\n                    </>\n                  ) : (\n                    <>\n                      <b>{number.format(x.contracted)} kW</b>\n                      <small className={x.excess > 0 ? "danger" : "ok"}>\n                        {x.excess > 0\n                          ? \`${'${number.format(x.excess)}'} kW de más\`\n                          : "Sin potencia sobrante"}\n                      </small>\n                    </>\n                  )}\n                </td>`;

if (source.includes(after)) {
  console.log("T1/T2 contracted display already patched.");
  process.exit(0);
}
if (source.includes(t1OnlyAfter)) {
  source = source.replace(t1OnlyAfter, after);
} else if (source.includes(before)) {
  source = source.replace(before, after);
} else {
  throw new Error("Could not find contracted/surplus table cell in app/page.tsx");
}
fs.writeFileSync(file, source);
console.log("Patched invoices: T1 shows N/A and T2 shows demand excess in red.");
