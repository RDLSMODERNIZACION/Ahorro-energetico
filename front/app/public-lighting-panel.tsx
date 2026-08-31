"use client";

import { useEffect, useMemo, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";
import "./public-lighting-panel.css";

const API = "https://ahorro-energetico.onrender.com";
const money = new Intl.NumberFormat("es-AR", { style:"currency", currency:"ARS", maximumFractionDigits:0 });
const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits:0 });

type PLHistory = {
  invoice_id?:string|null;
  billing_period:string;
  active_energy_kwh?:number|null;
  total_amount?:number|null;
  tariff_code?:string|null;
  invoice_number?:string|null;
};

type MeasurementClass = "MEDIDO_CONFIRMADO"|"MEDIDO_CON_ANOMALIAS"|"ESTIMADO_PROBABLE"|"SIN_EVIDENCIA";

type PLRow = {
  public_lighting_meter_id:string;
  meter_id?:string|null;
  linked:boolean;
  supply_number?:string;
  supply_contract?:string;
  meter_number?:string;
  address?:string;
  billing_period:string;
  invoice_id?:string|null;
  invoice_number?:string|null;
  active_energy_kwh?:number|null;
  average_12m_kwh?:number|null;
  previous_kwh?:number|null;
  change_percent?:number|null;
  total_amount?:number|null;
  tariff_code?:string|null;
  validation_status?:string|null;
  analysis_status:"normal"|"warning"|"critical"|"missing";
  analysis_reasons:string[];
  constant_consumption:boolean;
  measurement_class:MeasurementClass;
  measurement_label:string;
  measurement_detail:string;
  measurement_verified_periods:number;
  measurement_coherent_periods:number;
  measurement_incoherent_periods:number;
  reading_previous?:number|null;
  reading_current?:number|null;
  reading_multiplier?:number|null;
  reading_billed_kwh?:number|null;
  reading_coherent?:boolean|null;
  history:PLHistory[];
};

type PLResponse = {
  billing_period:string;
  periods:string[];
  summary:{
    expected:number; received:number; missing:number; unlinked?:number;
    total_kwh:number; total_amount:number;
    anomalies:number; warnings:number; critical:number;
    measured_confirmed:number;
    measured_with_anomalies:number;
    estimated_probable:number;
    measurement_unknown:number;
  };
  rows:PLRow[];
};

async function getAnalysis(session:Session, organizationId:string, period?:string):Promise<PLResponse>{
  const qs=period?`?billing_period=${period}`:"";
  const r=await fetch(`${API}/api/organizations/${organizationId}/public-lighting/analysis-fast${qs}`,{
    cache:"no-store",
    headers:{Authorization:`Bearer ${session.access_token}`}
  });
  if(!r.ok) throw new Error(await r.text()||`Error ${r.status}`);
  return r.json();
}

function statusLabel(row:PLRow){
  if(!row.linked) return "Sin vincular";
  if(row.analysis_status==="critical") return "Revisar urgente";
  if(row.analysis_status==="warning") return "Revisar";
  if(row.analysis_status==="missing") return "Sin factura";
  return "Normal";
}

function measurementShort(row:PLRow){
  if(row.measurement_class==="MEDIDO_CONFIRMADO") return "Medido";
  if(row.measurement_class==="MEDIDO_CON_ANOMALIAS") return "Medido · revisar";
  if(row.measurement_class==="ESTIMADO_PROBABLE") return "Estimado probable";
  return "Sin evidencia";
}

function readingSummary(row:PLRow){
  if(row.reading_previous==null||row.reading_current==null) return row.measurement_detail||"Sin lectura del período";
  const multiplier=row.reading_multiplier??1;
  return `Ant. ${number.format(row.reading_previous)} · Act. ${number.format(row.reading_current)} · x${number.format(multiplier)}`;
}

function asPublicLightingInvoice(invoice:any){
  if(!invoice)return invoice;
  return {
    ...invoice,
    invoice_measurements:(invoice.invoice_measurements||[]).map((m:any)=>({
      ...m,
      demand_kw:Number(m.active_energy_kwh||0),
      registered_demand_peak_kw:Number(m.active_energy_kwh||0),
      registered_demand_off_peak_kw:0,
      power_factor:undefined,
      resolved_power_factor:undefined,
      power_factor_penalized:false,
      reactive_surcharge_percent:0,
    }))
  };
}

export function PublicLightingPanel({
  session,organizationId,invoices,tariffSavings,epenOptimization
}:{
  session:Session;
  organizationId:string;
  invoices:any[];
  tariffSavings:any[];
  epenOptimization:any[];
}){
  const [data,setData]=useState<PLResponse|null>(null);
  const [period,setPeriod]=useState("");
  const [search,setSearch]=useState("");
  const [status,setStatus]=useState("all");
  const [measurement,setMeasurement]=useState("all");
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState("");
  const [selected,setSelected]=useState<PLRow|null>(null);
  const [sortKey,setSortKey]=useState<"consumption"|"amount"|null>(null);
  const [sortDir,setSortDir]=useState<"desc"|"asc">("desc");

  const latestGeneralPeriod=useMemo(()=>{
    const periods=invoices
      .map(i=>String(i.billing_period||i.period_start||"").slice(0,7))
      .filter(Boolean)
      .sort((a,b)=>b.localeCompare(a));
    return periods[0]||"";
  },[invoices]);

  useEffect(()=>{
    if(!period&&latestGeneralPeriod)setPeriod(latestGeneralPeriod);
  },[period,latestGeneralPeriod]);

  useEffect(()=>{
    if(!organizationId||!period)return;
    let cancelled=false;
    setLoading(true);
    setError("");

    getAnalysis(session,organizationId,period)
      .then(result=>{if(!cancelled)setData(result)})
      .catch(e=>!cancelled&&setError(e instanceof Error?e.message:"No se pudo cargar Alumbrado Público"))
      .finally(()=>!cancelled&&setLoading(false));

    return()=>{cancelled=true};
  },[session,organizationId,period]);

  const rows=useMemo(()=>{
    if(!data)return[];
    const q=search.trim().toLowerCase();
    const filtered=data.rows.filter(row=>{
      if(status!=="all"&&row.analysis_status!==status)return false;
      if(measurement!=="all"&&row.measurement_class!==measurement)return false;
      if(!q)return true;
      return [row.meter_number,row.supply_number,row.supply_contract,row.address,row.invoice_number,row.measurement_label]
        .some(v=>String(v||"").toLowerCase().includes(q));
    });

    if(!sortKey)return filtered;
    return [...filtered].sort((a,b)=>{
      const av=sortKey==="consumption"?Number(a.active_energy_kwh??-1):Number(a.total_amount??-1);
      const bv=sortKey==="consumption"?Number(b.active_energy_kwh??-1):Number(b.total_amount??-1);
      return sortDir==="desc"?bv-av:av-bv;
    });
  },[data,search,status,measurement,sortKey,sortDir]);

  function toggleSort(key:"consumption"|"amount"){
    if(sortKey===key)setSortDir(current=>current==="desc"?"asc":"desc");
    else {setSortKey(key);setSortDir("desc");}
  }

  const selectedHistoryRaw=selected?.meter_id
    ? invoices
        .filter(i=>String(i.meter_id)===String(selected.meter_id))
        .sort((a,b)=>String(a.billing_period||a.period_start).localeCompare(String(b.billing_period||b.period_start)))
    : [];

  const currentPeriodInvoice=selected?(
    (selected.invoice_id?invoices.find(i=>String(i.id)===String(selected.invoice_id)):undefined)
    ||(selected.meter_id?invoices.find(i=>
      String(i.meter_id)===String(selected.meter_id)
      &&String(i.billing_period||i.period_start||"").slice(0,7)===String(selected.billing_period).slice(0,7)
    ):undefined)
  ):null;

  const rawSelectedInvoice=currentPeriodInvoice
    ||(selectedHistoryRaw.length?selectedHistoryRaw[selectedHistoryRaw.length-1]:null);

  const selectedInvoice=rawSelectedInvoice?asPublicLightingInvoice(rawSelectedInvoice):null;
  const selectedHistory=selectedHistoryRaw.map(asPublicLightingInvoice);

  if(error)return <section className="panel pl-error">{error}</section>;
  if(!data)return <section className="panel pl-loading">{loading?"Analizando Alumbrado Público…":"Sin datos"}</section>;

  const ledSavingRate=0.55;
  const monthlyAmount=Number(data.summary.total_amount||0);
  const ledMonthlySaving=monthlyAmount*ledSavingRate;
  const ledAnnualSaving=ledMonthlySaving*12;

  return <div className="pl-module">
    <div className="pl-missing-shortcut">
      <button
        type="button"
        className={status==="missing"?"active":""}
        onClick={()=>setStatus(current=>current==="missing"?"all":"missing")}
      >
        <span>Sin facturación</span>
        <b>{data.summary.missing}</b>
      </button>
    </div>

    <section className="pl-kpis">
      <article><span>PERÍODO CONTROLADO</span><strong>{data.billing_period}</strong><small>último mes disponible al ingresar</small></article>
      <article><span>FACTURAS ESPERADAS</span><strong>{data.summary.expected}</strong><small>suministros clasificados como AP</small></article>
      <article className="green"><span>FACTURAS RECIBIDAS</span><strong>{data.summary.received}</strong><small>{data.summary.missing} faltantes</small></article>
      <article className={data.summary.missing?"alert":""}><span>FACTURAS FALTANTES</span><strong>{data.summary.missing}</strong><small>sin factura en {data.billing_period}</small></article>
    </section>

    <section className="pl-kpis" style={{gridTemplateColumns:"repeat(3,1fr)"}}>
      <article>
        <span>IMPORTE DEL MES</span>
        <strong>{money.format(monthlyAmount)}</strong>
        <small>{data.summary.received} facturas recibidas de {data.summary.expected}</small>
      </article>
      <article className="green">
        <span>AHORRO SI TODO FUERA LED</span>
        <strong>{money.format(ledMonthlySaving)}</strong>
        <small>escenario estimado 55% · ahorro mensual</small>
      </article>
      <article>
        <span>AHORRO LED ANUALIZADO</span>
        <strong>{money.format(ledAnnualSaving)}</strong>
        <small>ahorro del mes × 12 · escenario 55%</small>
      </article>
    </section>

    {(data.summary.unlinked||0)>0&&<section className="panel pl-error">Hay {data.summary.unlinked} suministro(s) de Alumbrado Público sin vincular a un medidor general.</section>}

    <section className="panel">
      <div className="panel-title pl-title"><div><h2>{status==="missing"?"Alumbrado Público sin facturación":"Análisis mensual de Alumbrado Público"}</h2><p>{status==="missing"?`${data.summary.missing} suministros sin factura en ${data.billing_period}`:"Consumo · lectura · tipo de medición · tarifa · importe"}</p></div></div>

      <div className="pl-filters">
        <label>Período<select value={period} onChange={e=>setPeriod(e.target.value)}>{data.periods.map(p=><option key={p} value={p}>{p}</option>)}</select></label>
        <label>Estado<select value={status} onChange={e=>setStatus(e.target.value)}><option value="all">Todos</option><option value="critical">Críticos</option><option value="warning">Revisar</option><option value="missing">Sin factura</option><option value="normal">Normales</option></select></label>
        <label>Medición<select value={measurement} onChange={e=>setMeasurement(e.target.value)}><option value="all">Todas</option><option value="MEDIDO_CONFIRMADO">Medidos</option><option value="MEDIDO_CON_ANOMALIAS">Medidos con anomalías</option><option value="ESTIMADO_PROBABLE">Estimados probables</option><option value="SIN_EVIDENCIA">Sin evidencia</option></select></label>
        <label className="pl-search">Buscar<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Medidor, suministro o dirección"/></label>
        <button onClick={()=>{setSearch("");setStatus("all");setMeasurement("all")}}>Limpiar</button>
      </div>

      <div className="pl-table-scroll"><div className="pl-table">
        <div className="pl-row pl-head">
          <span>MEDIDOR / SUMINISTRO</span>
          <span>UBICACIÓN</span>
          <button type="button" className={`pl-sort-head ${sortKey==="consumption"?"active":""}`} onClick={()=>toggleSort("consumption")} title="Ordenar por consumo">CONSUMO {sortKey==="consumption"?(sortDir==="desc"?"↓":"↑"):""}</button>
          <button type="button" className={`pl-sort-head ${sortKey==="amount"?"active":""}`} onClick={()=>toggleSort("amount")} title="Ordenar por importe">IMPORTE {sortKey==="amount"?(sortDir==="desc"?"↓":"↑"):""}</button>
          <span>TARIFA</span>
          <span>MEDICIÓN</span>
          <span>ANÁLISIS</span>
        </div>

        {rows.map(row=><button className={`pl-row pl-data ${row.analysis_status} measurement-${row.measurement_class.toLowerCase()}`} key={row.public_lighting_meter_id} onClick={()=>setSelected(row)}>
          <span><b>Medidor {row.meter_number||"S/D"}</b><small>Suministro {row.supply_number||"S/D"}</small></span>
          <span><b>{row.address||"Sin dirección"}</b><small>{row.linked?"Vinculado a factura general":"SIN VINCULAR"}</small></span>
          <span><b>{row.analysis_status==="missing"?"SIN FACTURA":row.active_energy_kwh==null?"—":`${number.format(row.active_energy_kwh)} kWh`}</b><small>{row.previous_kwh==null?"Sin mes anterior":`Anterior ${number.format(row.previous_kwh)} kWh`}</small></span>
          <span><b>{row.analysis_status==="missing"?"SIN FACTURA":row.total_amount==null?"—":money.format(row.total_amount)}</b><small>{row.analysis_status==="missing"?"faltante del período":"facturado"}</small></span>
          <span><b className={`pl-tariff ${row.tariff_code!=="T1AP"?"review":""}`}>{row.tariff_code||"S/D"}</b><small>EPEN</small></span>
          <span><em className={`pl-measurement ${row.measurement_class.toLowerCase()}`}>{measurementShort(row)}</em><small title={row.measurement_detail}>{readingSummary(row)}</small></span>
          <span><em className={`pl-status ${row.analysis_status}`}>{statusLabel(row)}</em><small>{row.analysis_reasons[0]||"Sin observaciones"}</small></span>
        </button>)}

        {!rows.length&&<div className="pl-empty">No hay registros para esos filtros.</div>}
      </div></div>
    </section>

    {selected&&selectedInvoice&&<div className="pl-individual-public-lighting"><InvoiceAnalysisPanel
      invoice={selectedInvoice}
      history={selectedHistory}
      tariffSavings={tariffSavings}
      optimization={epenOptimization.find(x=>String(x.meter_id)===String(selected.meter_id))}
      onClose={()=>setSelected(null)}
      backLabel="← Volver a Alumbrado Público"
      analysisLabel="ANÁLISIS INDIVIDUAL · ALUMBRADO PÚBLICO"
      allowNameEdit={false}
      hideLocationEditor={true}
    /></div>}

    {selected&&!selectedInvoice&&<section className="panel pl-error">
      Este suministro no tiene ninguna factura histórica disponible para abrir el análisis individual.
      <div><button onClick={()=>setSelected(null)}>Volver</button></div>
    </section>}
  </div>;
}
