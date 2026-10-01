"use client";
import type { PowerStrategy,T2Comparison } from './lib/t2-power';
import styles from './power-curve.module.css';
const money=new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS',maximumFractionDigits:0});
export function T2PowerComparison({model,strategy,onSelect}:{model:T2Comparison;strategy:PowerStrategy;onSelect:(s:PowerStrategy)=>void}){
 const chosen=model.scenarios.find(s=>s.id===strategy)!;
 return <section className={styles.t2Comparison} aria-label="Comparación de potencia T2">
 <h3>Alternativas de potencia T2</h3>
 <p>Precio de referencia: {money.format(model.rate)}/kW·mes · factura {model.ratePeriod || 'sin datos'}. Se mantiene constante para comparar doce meses. Máximo de los dos últimos años disponibles por mes de consumo, usando potencia registrada para facturación.</p>
 {!model.complete?<p role="status">No se calcula ahorro anual: {model.missing.length?`faltan mediciones de ${model.missing.join(', ')}. `:''}{model.outOfRange?'La demanda alcanza 50 kW: revisar encuadramiento tarifario. ':''}{!model.rate?'Falta precio de potencia. ':''}{model.currentKw<10?'Revisar potencia contratada actual.':''}</p>:<>
 <div className={styles.t2Scroll}><table><thead><tr><th>Alternativa</th><th>Contratación anual</th><th>Excesos anuales</th><th>Costo total</th><th>Ahorro neto anual</th><th>Meses con exceso</th></tr></thead><tbody>{model.scenarios.map(s=><tr key={s.id}><td><label><input type="radio" name="power-strategy" checked={strategy===s.id} onChange={()=>onSelect(s.id)}/>{s.label}</label></td><td>{money.format(s.contractedCost)}</td><td>{money.format(s.excessCost)}</td><td>{money.format(s.annualCost)}</td><td>{money.format(s.annualSavingNet)}</td><td>{s.excessMonths}</td></tr>)}</tbody></table></div>
 <p>Comparación neta frente a mantener {model.currentKw} kW, incluidos sus excesos. {model.hasTaxes?`Ahorro seleccionado con IVA y percepción estimados de la factura: ${money.format(chosen.annualSaving)}.`:'Impuestos no estimados: faltan datos fiscales; los ahorros se muestran netos.'} No incluye energía ni factor de potencia.</p>
 <div className={styles.t2Scroll}><table><thead><tr><th>Mes de consumo</th><th>Demanda de referencia</th><th>Contratada propuesta</th><th>Exceso previsto</th><th>Ahorro neto</th></tr></thead><tbody>{chosen.rows.map(r=><tr key={r.monthNumber}><td>{r.month}</td><td>{r.demand} kW</td><td>{r.proposalKw} kW</td><td>{r.excessKw} kW</td><td>{money.format(r.savingNet)}</td></tr>)}</tbody></table></div>
 {chosen.excessMonths>0&&<p>Esta alternativa prevé excesos. Su menor costo no garantiza disponibilidad de potencia: revisar la necesidad operativa y las condiciones de EPEN antes de registrar su aplicación.</p>}
 </>}
 {model.decline.length>0&&<p>Revisar cambio operativo: la demanda cayó más del 30% frente al año anterior en {model.decline.join(', ')}. La proyección conserva el mayor valor histórico.</p>}
 </section>;
}
