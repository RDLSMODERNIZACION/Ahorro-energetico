"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import styles from "./epen-optimization.module.css";

const API = process.env.NEXT_PUBLIC_API_URL || "https://ahorro-energetico.onrender.com";
const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });

type Block = {
  status:string;
  monthly_saving_before_taxes?:number|null;
  annual_saving_before_taxes?:number|null;
  [key:string]:unknown;
};
export type EpenOptimizationMeter = {
  meter_id:string; meter_number?:string; tracking_code?:string; supply_number?:string; service_name?:string;
  period:string; current_tariff:string; voltage_level:string; consumption_kwh:number; latest_max_demand_kw:number;
  max_demand_12m_kw:number; periods_available:number;
  t3:Block & {current_peak_kw:number;current_off_peak_kw:number;max_registered_peak_12m_kw:number;max_registered_off_peak_12m_kw:number;recommended_peak_kw:number;recommended_off_peak_kw:number};
  t4:Block & {target_tariff?:string;months_over_100kw_last12:number;current_t3_cost_before_taxes?:number;t4_cost_before_taxes?:number;optimized_monthly_saving_before_taxes?:number};
  mt:Block & {current_bt_cost_before_taxes?:number;simulated_mt_cost_before_taxes?:number;estimated_investment?:number;payback_months?:number};
};
export type EpenOptimizationResponse = {
  period:string; taxes_included:boolean; note:string;
  summary:{t3_candidates:number;t4_candidates:number;mt_candidates:number;t3_monthly_saving_before_taxes:number;t4_monthly_saving_before_taxes:number;mt_monthly_saving_before_taxes:number};
  meters:EpenOptimizationMeter[];
};

async function getData(session:Session, organizationId:string):Promise<EpenOptimizationResponse>{
  const r=await fetch(`${API}/api/organizations/${organizationId}/epen-optimization?v=1`,{cache:"no-store",headers:{Authorization:`Bearer ${session.access_token}`}});
  if(!r.ok)throw new Error(await r.text()||`Error ${r.status}`);
  return r.json();
}

function statusLabel(value:string){
  const labels:Record<string,string>={candidate:"Candidato",optimized:"Sin reducción detectada",missing_contracted_bands:"Falta contrato punta/fuera punta",missing_registered_band_demands:"Faltan demandas por banda",requires_mt:"Requiere MT",insufficient_history:"Faltan 12 meses",not_eligible_history:"No cumple 12/12 >100 kW",strong:"Candidato fuerte",preliminary:"Estudio preliminar",not_candidate:"No prioritario",not_t3:"No T3"};
  return labels[value]||value;
}

export function EpenOptimizationPanel({session,organizationId,onOpenMeter}:{session:Session;organizationId:string;onOpenMeter?:(meterId:string)=>void}){
  const[data,setData]=useState<EpenOptimizationResponse|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState("");
  const load=useCallback(async()=>{if(!organizationId)return;setLoading(true);setError("");try{setData(await getData(session,organizationId))}catch(e){setError(e instanceof Error?e.message:"No se pudo cargar el análisis EPEN")}finally{setLoading(false)}},[session,organizationId]);
  useEffect(()=>{load()},[load]);

  const t3=useMemo(()=>data?.meters.filter(x=>["T3","T3A"].includes(x.current_tariff))||[],[data]);
  const t4=useMemo(()=>data?.meters.filter(x=>x.t4.status==="candidate"||x.t4.status==="insufficient_history")||[],[data]);
  const mt=useMemo(()=>data?.meters.filter(x=>["strong","candidate","preliminary"].includes(x.mt.status))||[],[data]);

  return <section className={styles.wrap}>
    <div className={styles.hero}>
      <div><span>OPTIMIZACIÓN AVANZADA EPEN</span><h2>T3 · T4 · Baja a Media Tensión</h2><p>Simula oportunidades con el cuadro tarifario del período. Los valores se muestran antes de impuestos.</p></div>
      <button onClick={load} disabled={loading}>{loading?"Calculando…":"Recalcular"}</button>
    </div>
    {error&&<div className={styles.error}>{error}</div>}
    {data&&<>
      <div className={styles.cards}>
        <article><span>T3 punta / fuera punta</span><b>{data.summary.t3_candidates}</b><strong>{money.format(data.summary.t3_monthly_saving_before_taxes)}<small>/mes</small></strong></article>
        <article><span>Candidatos T3 → T4</span><b>{data.summary.t4_candidates}</b><strong>{money.format(data.summary.t4_monthly_saving_before_taxes)}<small>/mes</small></strong></article>
        <article><span>Candidatos BT → MT</span><b>{data.summary.mt_candidates}</b><strong>{money.format(data.summary.mt_monthly_saving_before_taxes)}<small>/mes</small></strong></article>
      </div>

      <div className={styles.block}>
        <div className={styles.head}><div><span>1</span><div><h3>Potencia contratada T3</h3><p>Separa capacidad en punta y fuera de punta y compara contra las máximas registradas de los últimos 12 períodos.</p></div></div></div>
        <div className={styles.table}><table><thead><tr><th>Suministro</th><th>Actual punta</th><th>Actual fuera punta</th><th>Máx. punta 12m</th><th>Máx. fuera punta 12m</th><th>Recomendado</th><th>Ahorro/mes</th><th>Estado</th></tr></thead><tbody>
          {t3.map(x=><tr key={x.meter_id} onClick={()=>onOpenMeter?.(x.meter_id)}><td><b>{x.service_name||`Medidor ${x.meter_number||"S/D"}`}</b><small>{x.current_tariff} · {x.voltage_level} · {x.supply_number||x.tracking_code||""}</small></td><td>{number.format(x.t3.current_peak_kw)} kW</td><td>{number.format(x.t3.current_off_peak_kw)} kW</td><td>{number.format(x.t3.max_registered_peak_12m_kw)} kW</td><td>{number.format(x.t3.max_registered_off_peak_12m_kw)} kW</td><td><b>{number.format(x.t3.recommended_peak_kw)} / {number.format(x.t3.recommended_off_peak_kw)} kW</b><small>punta / fuera punta</small></td><td className={styles.saving}>{x.t3.monthly_saving_before_taxes!=null?money.format(x.t3.monthly_saving_before_taxes):"—"}</td><td><span className={styles.status}>{statusLabel(x.t3.status)}</span></td></tr>)}
          {!t3.length&&<tr><td colSpan={8}>No hay suministros T3 cargados.</td></tr>}
        </tbody></table></div>
      </div>

      <div className={styles.block}>
        <div className={styles.head}><div><span>2</span><div><h3>Comparación T3 → T4</h3><p>Marca candidatos MT/AT y exige 12 períodos con demanda de al menos 100 kW para considerarlos candidatos reglamentarios.</p></div></div></div>
        <div className={styles.table}><table><thead><tr><th>Suministro</th><th>Historial</th><th>T3 simulado</th><th>T4 simulado</th><th>Ahorro/mes</th><th>Estado</th></tr></thead><tbody>
          {t4.map(x=><tr key={x.meter_id} onClick={()=>onOpenMeter?.(x.meter_id)}><td><b>{x.service_name||`Medidor ${x.meter_number||"S/D"}`}</b><small>{x.current_tariff} · {x.voltage_level}</small></td><td><b>{x.t4.months_over_100kw_last12}/12</b><small>meses ≥100 kW</small></td><td>{x.t4.current_t3_cost_before_taxes!=null?money.format(x.t4.current_t3_cost_before_taxes):"—"}</td><td>{x.t4.t4_cost_before_taxes!=null?money.format(x.t4.t4_cost_before_taxes):"—"}<small>{x.t4.target_tariff||"T4"}</small></td><td className={styles.saving}>{x.t4.monthly_saving_before_taxes!=null?money.format(x.t4.monthly_saving_before_taxes):"—"}</td><td><span className={styles.status}>{statusLabel(x.t4.status)}</span><small>Requiere contrato EPEN</small></td></tr>)}
          {!t4.length&&<tr><td colSpan={6}>No hay candidatos T4 con los datos disponibles.</td></tr>}
        </tbody></table></div>
      </div>

      <div className={styles.block}>
        <div className={styles.head}><div><span>3</span><div><h3>Estudio Baja Tensión → Media Tensión</h3><p>Compara la misma categoría y demanda con los cargos oficiales BT y MT del mismo período.</p></div></div></div>
        <div className={styles.table}><table><thead><tr><th>Suministro</th><th>Demanda 12m</th><th>BT simulado</th><th>MT simulado</th><th>Ahorro/mes</th><th>Prioridad</th></tr></thead><tbody>
          {mt.map(x=><tr key={x.meter_id} onClick={()=>onOpenMeter?.(x.meter_id)}><td><b>{x.service_name||`Medidor ${x.meter_number||"S/D"}`}</b><small>{x.current_tariff} · hoy {x.voltage_level}</small></td><td>{number.format(x.max_demand_12m_kw)} kW</td><td>{x.mt.current_bt_cost_before_taxes!=null?money.format(x.mt.current_bt_cost_before_taxes):"—"}</td><td>{x.mt.simulated_mt_cost_before_taxes!=null?money.format(x.mt.simulated_mt_cost_before_taxes):"—"}</td><td className={styles.saving}>{x.mt.monthly_saving_before_taxes!=null?money.format(x.mt.monthly_saving_before_taxes):"—"}</td><td><span className={styles.status}>{statusLabel(x.mt.status)}</span><small>Requiere factibilidad EPEN</small></td></tr>)}
          {!mt.length&&<tr><td colSpan={6}>No hay suministros BT con demanda ≥50 kW para estudiar.</td></tr>}
        </tbody></table></div>
      </div>
      <p className={styles.note}>{data.note}</p>
    </>}
  </section>;
}

