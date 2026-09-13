import { readFileSync, writeFileSync } from "node:fs";

const path = new URL("../app/meter-change-control.tsx", import.meta.url);
let s = readFileSync(path, "utf8");
if (s.includes("EDIT_POWER_LIKE_REGISTER_V1")) process.exit(0);

s = s.replace(
  '    [editNotes, setEditNotes] = useState(""),\n    [editStatus, setEditStatus] =',
  '    [editNotes, setEditNotes] = useState(""),\n    // EDIT_POWER_LIKE_REGISTER_V1\n    [editPowerValues, setEditPowerValues] = useState<Record<number, string>>({}),\n    [editStatus, setEditStatus] =',
);

s = s.replace(
  '    setEditNew(row.new_value || "");\n    setEditNotes(row.notes || "");',
  '    setEditNew(row.new_value || "");\n    if (row.change_type === "contracted_power") {\n      const months = Array.isArray(row.details?.months) ? row.details.months : [];\n      const values: Record<number, string> = {};\n      for (const item of months as Array<Record<string, unknown>>) {\n        const m = Number(item.monthNumber || 0);\n        const v = Number(item.effective_kw || 0);\n        if (m && v) values[m] = String(v);\n      }\n      setEditPowerValues(values);\n    } else setEditPowerValues({});\n    setEditNotes(row.notes || "");',
);

const updateOld = '    const { error: updateError } = await supabase\n      .from("meter_change_controls")\n      .update({\n        effective_period: `${editPeriod}-01`,\n        previous_value: editPrevious || null,\n        new_value: editNew || null,\n        notes: editNotes || null,';
const updateNew = '    const editingRow = controls.find((row) => row.id === editingId);\n    let nextDetails = editingRow?.details || {};\n    let nextNewValue = editNew || null;\n    if (editingRow?.change_type === "contracted_power") {\n      const oldMonths = Array.isArray(editingRow.details?.months) ? editingRow.details.months as Array<Record<string, unknown>> : [];\n      const months = powerProposals.map((p) => {\n        const old = oldMonths.find((x) => Number(x.monthNumber) === p.monthNumber) || {};\n        return { ...old, month: p.month, monthNumber: p.monthNumber, proposalKw: Number(old.proposalKw || p.proposalKw || 0), method: String(old.method || p.method || "mensual"), quarter: String(old.quarter || p.quarter || ""), latestKw: Number(old.latestKw || p.latestKw || 0), latestPeriod: String(old.latestPeriod || p.latestPeriod || ""), effective_kw: Number(editPowerValues[p.monthNumber] || old.effective_kw || p.proposalKw || 0) };\n      });\n      nextDetails = { ...nextDetails, months };\n      const monthNumber = Number(editPeriod.slice(5, 7));\n      const effectiveKw = Number(editPowerValues[monthNumber] || months.find((x) => x.monthNumber === monthNumber)?.effective_kw || 0);\n      nextNewValue = effectiveKw > 0 ? number.format(effectiveKw) + " kW" : editingRow.new_value || null;\n    }\n    const { error: updateError } = await supabase\n      .from("meter_change_controls")\n      .update({\n        effective_period: `${editPeriod}-01`,\n        previous_value: editPrevious || null,\n        new_value: nextNewValue,\n        details: nextDetails,\n        notes: editNotes || null,';
if (!s.includes(updateOld)) throw new Error("update block not found");
s = s.replace(updateOld, updateNew);

const fieldsOld = '                            <label>\n                              Valor anterior\n                              <input\n                                value={editPrevious}\n                                onChange={(event) =>\n                                  setEditPrevious(event.target.value)\n                                }\n                              />\n                            </label>\n                            <label>\n                              Valor aplicado\n                              <input\n                                value={editNew}\n                                onChange={(event) =>\n                                  setEditNew(event.target.value)\n                                }\n                              />\n                            </label>';

const fieldsNew = `                            {row.change_type === "contracted_power" ? (
                              <div className="wide">
                                <p style={{ margin: "0 0 10px", color: "#66766e" }}>Editá la potencia contratada mes por mes, igual que al registrar la mejora.</p>
                                <div className="improvement-power-table">
                                  <div className="improvement-power-head">
                                    <span>Mes</span><span>Potencia real anterior</span><span>Potencia real actual</span><span>Propuesta</span><span>Potencia efectivamente contratada</span>
                                  </div>
                                  {powerProposals.map((proposal) => {
                                    const savedMonths = Array.isArray(row.details?.months) ? row.details.months as Array<Record<string, unknown>> : [];
                                    const saved = savedMonths.find((item) => Number(item.monthNumber) === proposal.monthNumber);
                                    const proposalKw = Number(saved?.proposalKw || proposal.proposalKw || 0);
                                    const currentValue = editPowerValues[proposal.monthNumber] ?? String(Number(saved?.effective_kw || proposalKw || 0));
                                    return <div key={proposal.monthNumber}>
                                      <b>{proposal.month}</b>
                                      {[1, 0].map((index) => {
                                        const observation = proposal.observations[index];
                                        return <span key={index}>{observation ? number.format(observation.demand) + " kW" : "S/D"}<small>{observation ? "Consumo " + observation.period : "Sin medición histórica"}</small>{observation?.billingPeriod && <small>Factura {observation.billingPeriod}</small>}</span>;
                                      })}
                                      <span>{number.format(proposalKw)} kW<small>{String(saved?.method || proposal.method) === "trimestral" ? "Trimestre " + String(saved?.quarter || proposal.quarter || "") : "Propuesta mensual"}</small></span>
                                      <label><input type="number" min="0" step="0.1" value={currentValue} onChange={(event) => setEditPowerValues((values) => ({ ...values, [proposal.monthNumber]: event.target.value }))} /> kW</label>
                                    </div>;
                                  })}
                                </div>
                              </div>
                            ) : (<>
                              <label>Valor anterior<input value={editPrevious} onChange={(event) => setEditPrevious(event.target.value)} /></label>
                              <label>Valor aplicado<input value={editNew} onChange={(event) => setEditNew(event.target.value)} /></label>
                            </>)}`;
if (!s.includes(fieldsOld)) throw new Error("edit fields not found");
s = s.replace(fieldsOld, fieldsNew);

writeFileSync(path, s, "utf8");
console.log("Applied full monthly editor for contracted power changes.");
