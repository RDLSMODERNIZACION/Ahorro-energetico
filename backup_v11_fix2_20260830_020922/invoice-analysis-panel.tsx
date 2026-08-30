"use client";

import {useMemo, useState, useEffect} from "react";
import { MeterLocationEditor } from "./meter-location-editor";
import { supabase } from "./lib/supabase";
import type { EpenOptimizationMeter } from "./epen-optimization-panel";

type Measurement={
  active_energy_kwh?:number;
  reactive_energy_kvarh?:number;
  demand_kw?:number;
  registered_demand_peak_kw?:number;
  registered_demand_off_peak_kw?:number;
  power_factor?:number;
  tangent_phi?:number;
  reactive_surcharge_percent?:number;
  meter_number?:string;
  measurement_type?:string;
};
type Line={concept_code?:string;description?:string;quantity?:number;unit_price?:number;net_amount?:number};
type Meter={
  id:string;tracking_code?:string;meter_number?:string;supply_number?:string;contract_number?:string;
  service_code?:string;service_name?:string;cadastral_number?:string;voltage_level?:string;
  contracted_kw_peak?:number;contracted_kw_off_peak?:number;sites?:{name?:string;address?:string};
};
type Invoice={
  id:string;meter_id:string;invoice_number?:string;billing_period?:string;period_start:string;period_end:string;
  issue_date?:string;due_date?:string;total_amount:number;amount_due?:number;current_tariff_code?:string;
  tariff_name?:string;voltage_level?:string;contracted_kw_peak?:number;contracted_kw_off_peak?:number;vat_amount?:number;previous_debt_amount?:number;
  meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:Line[];
};
type TariffSaving={meter_id:string;billing_period:string;current_tariff?:string;recommended_tariff?:string;current_cost_with_vat?:number;recommended_cost_with_vat?:number;monthly_saving_with_vat:number;annual_saving_with_vat?:number};
type AdvancedTariffHistoryPoint={
  billing_period:string;
  current_tariff:string;
  recommended_tariff:string;
  current_cost:number;
  recommended_cost:number;
  monthly_saving:number;
  annualized_saving:number;
  capacity_kw:number;
};
type AdvancedTariffHistoryResponse={
  meter_id:string;
  mode:"t4"|"none";
  current_tariff?:string;
  recommended_tariff?:string;
  taxes_included?:boolean;
  points:AdvancedTariffHistoryPoint[];
};
type Metric="kwh"|"amount"|"demand"|"pf"|"tariff";

const nf=new Intl.NumberFormat("es-AR",{maximumFractionDigits:0});
const dec=new Intl.NumberFormat("es-AR",{maximumFractionDigits:3});
const API="https://ahorro-energetico.onrender.com";
const money=new Intl.NumberFormat("es-AR",{style:"currency",currency:"ARS",maximumFractionDigits:0});

function periodOf(i:Invoice){return String(i.billing_period||i.period_start).slice(0,7)}
function contractedBands(i:Invoice){
  const lines=i.invoice_lines||[];
  const dep=Math.max(0,...lines.filter(x=>x.concept_code==="DEP"||x.concept_code==="DEM").map(x=>Number(x.quantity||0)));
  const dfp=Math.max(0,...lines.filter(x=>x.concept_code==="DFP").map(x=>Number(x.quantity||0)));
  const peak=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||dep||0);
  const offPeak=Number(i.contracted_kw_off_peak||i.meters?.contracted_kw_off_peak||dfp||0);
  return{peak,offPeak};
}
function labelPeriod(period:string){const[y,m]=period.split("-").map(Number);return new Date(y,m-1,1).toLocaleString("es-AR",{month:"short",year:"2-digit"}).replace(".","")}
function values(i:Invoice){
  const ms=i.invoice_measurements||[];
  const kwh=ms.reduce((s,m)=>s+Number(m.active_energy_kwh||0),0);
  const kvarh=ms.reduce((s,m)=>s+Number(m.reactive_energy_kvarh||0),0);
  const demand=Math.max(0,...ms.map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));
  const contracted=contractedBands(i).peak;
  const pfs=ms.map(m=>Number(m.power_factor||0)).filter(v=>v>0);
  const pf=pfs.length?Math.min(...pfs):0;
  const surcharge=Math.max(0,...ms.map(m=>Number(m.reactive_surcharge_percent||0)));
  return{kwh,kvarh,demand,contracted,pf,surcharge};
}
function metricValue(i:Invoice,m:Metric){
  const v=values(i);
  if(m==="amount")return Number(i.total_amount||0);
  if(m==="demand")return v.demand;
  if(m==="pf")return v.pf;
  return v.kwh;
}
function fmt(metric:Metric,value:number){
  if(metric==="amount")return money.format(value);
  if(metric==="demand")return `${nf.format(value)} kW`;
  if(metric==="pf")return value?value.toFixed(3):"S/D";
  return `${nf.format(value)} kWh`;
}

function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()]
      .sort((a,b)=>a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period,row])=>({
        period,
        row,
        value:Math.max(0,Number(row.monthly_saving||0))
      }));
  },[rows]);

  if(!data.length||!data.some(d=>d.value>0)){
    return <div className="invoice-tariff-no-data">
      <b>Sin ahorro tarifario valorizado</b>
      <span>No hay una simulación mensual disponible para este medidor.</span>
    </div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  const axis=(value:number)=>{
    if(value>=1000000)return `$ ${(value/1000000).toLocaleString("es-AR",{maximumFractionDigits:1})} M`;
    if(value>=1000)return `$ ${(value/1000).toLocaleString("es-AR",{maximumFractionDigits:0})} mil`;
    return money.format(value);
  };

  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}>
          <line x1={left} x2={width-right} y1={y} y2={y}/>
          <text x={left-10} y={y+4} textAnchor="end">{axis(max*step)}</text>
        </g>
      })}

      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        return <g
          className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {d.row.current_tariff||"Actual"} → {d.row.recommended_tariff||"Propuesta"} · {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>
  </div>
}

function InvoiceTrend({rows,metric,selectedPeriod,onPeriod}:{rows:Invoice[];metric:Metric;selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,Invoice>();
    for(const row of rows){
      const p=periodOf(row);
      const current=map.get(p);
      if(!current||String(row.issue_date||row.id)>String(current.issue_date||current.id))map.set(p,row);
    }
    return [...map.entries()]
      .sort((a,b)=>a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period,invoice])=>({
        period,
        invoice,
        value:metricValue(invoice,metric),
        contracted:values(invoice).contracted
      }));
  },[rows,metric]);

  const width=1280,height=330,left=70,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(
    1,
    ...data.map(d=>d.value),
    ...(metric==="demand"?data.map(d=>d.contracted):[])
  )*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}>
          <line x1={left} x2={width-right} y1={y} y2={y}/>
          <text x={left-10} y={y+4} textAnchor="end">
            {metric==="pf"?(max*step).toFixed(2):nf.format(max*step)}
          </text>
        </g>
      })}

      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        return <g
          className={`invoice-analysis-bar${metric==="pf"&&d.value>0&&d.value<.95?" bad-pf":""}${metric==="pf"&&d.value>=.95?" good-pf":""}${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={y} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {fmt(metric,d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}

      {metric==="pf"&&<g className="invoice-pf-limit">
        <line x1={left} x2={width-right}
          y1={top+plotH-(0.95/max)*plotH}
          y2={top+plotH-(0.95/max)*plotH}/>
        <text x={width-right-4}
          y={top+plotH-(0.95/max)*plotH-7}
          textAnchor="end">Límite cos φ 0,95</text>
      </g>}

      {metric==="demand"&&data.map((d,index)=>d.contracted>0?
        <line
          key={`c-${d.period}`}
          className="invoice-contract-line"
          x1={left+index*slot}
          x2={left+(index+1)*slot}
          y1={top+plotH-(d.contracted/max)*plotH}
          y2={top+plotH-(d.contracted/max)*plotH}
        />:null)}
    </svg>

    {metric==="pf"&&<div className="invoice-pf-legend">
      <span><i className="good"/>Correcto: cos φ ≥ 0,95</span>
      <span><i className="bad"/>Revisar: cos φ &lt; 0,95</span>
    </div>}
  </div>
}
export function InvoiceAnalysisPanel({invoice,history,tariffSavings,optimization,onClose}:{invoice:Invoice;history:Invoice[];tariffSavings:TariffSaving[];optimization?:EpenOptimizationMeter;onClose:()=>void}){
  const[metric,setMetric]=useState<Metric>("kwh");
  const[advancedTariffHistory,setAdvancedTariffHistory]=useState<AdvancedTariffHistoryResponse|null>(null);
  const[editingName,setEditingName]=useState(false);
  const[nameDraft,setNameDraft]=useState(invoice.meters?.service_name||invoice.meters?.sites?.name||"");
  const[displayName,setDisplayName]=useState(invoice.meters?.service_name||invoice.meters?.sites?.name||"Servicio sin nombre");
  const[nameBusy,setNameBusy]=useState(false);
  const[nameError,setNameError]=useState("");
  const[selectedPeriod,setSelectedPeriod]=useState(periodOf(invoice));
  const selected=history.find(i=>periodOf(i)===selectedPeriod)||invoice;
  const v=values(selected);
  const contractedBand=contractedBands(selected);
  const isT3=["T3","T3A"].includes(String(selected.current_tariff_code||"").toUpperCase());
  const currentVoltage=String(selected.voltage_level||selected.meters?.voltage_level||"").toUpperCase();
  const powerLines=(selected.invoice_lines||[]).filter(x=>x.concept_code==="DEM"||x.concept_code==="DEP");
  const rate=Math.max(0,...powerLines.map(x=>Number(x.unit_price||0)));
  const excess=Math.max(0,v.contracted-v.demand);
  const powerSaving=excess*rate*1.30;
  const reactiveSaving=(selected.invoice_lines||[]).filter(x=>x.concept_code==="COS").reduce((s,x)=>s+Math.max(0,Number(x.net_amount||0)),0)*1.30;
  const tariffSaving=Number(tariffSavings.find(x=>x.meter_id===selected.meter_id&&String(x.billing_period).slice(0,7)===periodOf(selected))?.monthly_saving_with_vat||0);
  const totalSaving=powerSaving+reactiveSaving+tariffSaving;
  const m=selected.meters||invoice.meters;
  const sorted=[...history].sort((a,b)=>periodOf(a).localeCompare(periodOf(b)));
  useEffect(()=>{
    let cancelled=false;
    async function loadTariffHistory(){
      try{
        const{data}=await supabase.auth.getSession();
        if(!data.session||!selected.meter_id)return;
        const response=await fetch(`${API}/api/meters/${selected.meter_id}/tariff-saving-history`,{
          cache:"no-store",
          headers:{Authorization:`Bearer ${data.session.access_token}`}
        });
        if(!response.ok)throw new Error(await response.text());
        const json=await response.json() as AdvancedTariffHistoryResponse;
        if(!cancelled)setAdvancedTariffHistory(json);
      }catch{
        if(!cancelled)setAdvancedTariffHistory(null);
      }
    }
    loadTariffHistory();
    return()=>{cancelled=true};
  },[selected.meter_id]);
  async function saveMeterName(){
    const clean=nameDraft.trim();
    if(clean.length<2){setNameError("Ingresá un nombre válido.");return}
    setNameBusy(true);setNameError("");
    try{
      const{data}=await supabase.auth.getSession();
      if(!data.session)throw new Error("Sesión vencida");
      const response=await fetch(`${API}/api/meters/${selected.meter_id}/name`,{
        method:"PUT",
        headers:{Authorization:`Bearer ${data.session.access_token}`,"Content-Type":"application/json"},
        body:JSON.stringify({service_name:clean})
      });
      const body=await response.text();
      if(!response.ok){
        let message=body;
        try{message=JSON.parse(body).detail||body}catch{}
        throw new Error(message);
      }
      setDisplayName(clean);
      if(m)m.service_name=clean;
      setEditingName(false);
    }catch(error){
      setNameError(error instanceof Error?error.message:"No se pudo guardar el nombre");
    }finally{setNameBusy(false)}
  }
  return <div className="invoice-analysis-backdrop">
    <div className="invoice-analysis-page">
      <div className="invoice-analysis-top">
        <div>
          <button className="invoice-analysis-back" onClick={onClose}>← Volver a facturas</button>
          <small>ANÁLISIS INDIVIDUAL DE FACTURA</small>
          <div className="invoice-name-row">
            {editingName?
              <div className="invoice-name-editor">
                <input value={nameDraft} onChange={e=>setNameDraft(e.target.value)} autoFocus/>
                <button className="save" onClick={saveMeterName} disabled={nameBusy}>{nameBusy?"Guardando…":"Guardar"}</button>
                <button className="cancel" onClick={()=>{setEditingName(false);setNameError("");setNameDraft(displayName)}}>Cancelar</button>
              </div>
              :<>
                <h2>{displayName}</h2>
                <button className="invoice-edit-name" onClick={()=>{setNameDraft(displayName);setEditingName(true)}}>✎ Editar nombre</button>
              </>
            }
          </div>
          {nameError&&<div className="invoice-name-error">{nameError}</div>}
          <p>{m?.tracking_code} · Medidor {m?.meter_number||"S/D"} · Suministro {m?.supply_number||"S/D"}</p>
        </div>
        <div className="invoice-analysis-period">
          <span>Factura seleccionada</span>
          <b>{periodOf(selected)}</b>
          <small>{selected.invoice_number||"S/D"}</small>
        </div>
      </div>

      <div className="invoice-analysis-kpis">
        <article><span>Consumo</span><b>{nf.format(v.kwh)} kWh</b><small>energía activa del período</small></article>
        <article><span>Demanda máxima</span><b>{nf.format(v.demand)} kW</b><small>registrada en factura</small></article>
        {isT3?<>
        <article className={contractedBand.peak>0?"warn":""}><span>Potencia contratada punta</span><b>{contractedBand.peak>0?`${nf.format(contractedBand.peak)} kW`:"S/D"}</b><small>capacidad convenida en horas punta</small></article>
        <article className={contractedBand.offPeak>0?"warn":""}><span>Potencia contratada fuera punta</span><b>{contractedBand.offPeak>0?`${nf.format(contractedBand.offPeak)} kW`:"S/D"}</b><small>capacidad convenida en resto + valle</small></article>
      </>:<article className={excess>0?"warn":""}><span>Potencia contratada</span><b>{nf.format(v.contracted)} kW</b><small>{excess>0?`${nf.format(excess)} kW por encima de la demanda`:"sin sobrante detectado"}</small></article>}
        <article className={v.pf>0&&v.pf<.95?"warn":""}><span>Factor de potencia</span><b>{v.pf?v.pf.toFixed(3):"S/D"}</b><small>{v.surcharge>0?`recargo ${v.surcharge}%`:"sin recargo detectado"}</small></article>
        <article><span>Importe factura</span><b>{money.format(Number(selected.total_amount||0))}</b><small>importe total</small></article>
        <article className="saving"><span>Ahorro potencial</span><b>{money.format(totalSaving)}</b><small>{money.format(totalSaving*12)} anualizado</small></article>
      </div>

      <section className="invoice-analysis-panel">
        <div className="invoice-analysis-chart-head">
          <div>
            <h3>Evolución histórica del medidor</h3>
            <p>Hasta 24 meses. Tocá una barra para abrir esa factura.</p>
          </div>
          <div className="invoice-analysis-metrics">
            <button className={metric==="kwh"?"active":""} onClick={()=>setMetric("kwh")}>Consumo</button>
            <button className={metric==="amount"?"active":""} onClick={()=>setMetric("amount")}>Importe</button>
            <button className={metric==="demand"?"active":""} onClick={()=>setMetric("demand")}>Demanda</button>
            <button className={metric==="pf"?"active":""} onClick={()=>setMetric("pf")}>Factor potencia</button>
            <button className={metric==="tariff"?"active":""} onClick={()=>setMetric("tariff")}>Ahorro tarifario</button>
          </div>
        </div>

        {metric==="tariff" ? (() => {
          const legacyRows=tariffSavings
            .filter(x=>x.meter_id===selected.meter_id)
            .map(x=>({
              billing_period:String(x.billing_period).slice(0,7),
              monthly_saving:Number(x.monthly_saving_with_vat||0),
              current_tariff:x.current_tariff,
              recommended_tariff:x.recommended_tariff
            }));

          const advancedRows=(advancedTariffHistory?.points||[]).map(x=>({
            billing_period:String(x.billing_period).slice(0,7),
            monthly_saving:Number(x.monthly_saving||0),
            current_tariff:x.current_tariff,
            recommended_tariff:x.recommended_tariff
          }));

          const chartRows=advancedRows.some(x=>x.monthly_saving>0) ? advancedRows : legacyRows;

          return <TariffSavingTrend
            rows={chartRows}
            selectedPeriod={periodOf(selected)}
            onPeriod={setSelectedPeriod}
          />;
        })() : (
          <InvoiceTrend
            rows={sorted}
            metric={metric}
            selectedPeriod={periodOf(selected)}
            onPeriod={setSelectedPeriod}
          />
        )}
      </section>
      <div className="invoice-analysis-grid">
        <section className="invoice-analysis-panel">
          <h3>Detalle completo de la factura</h3>
          <div className="invoice-analysis-details">
            <div><span>Período</span><b>{periodOf(selected)}</b></div>
            <div><span>Número de factura</span><b>{selected.invoice_number||"S/D"}</b></div>
            <div><span>Emisión</span><b>{selected.issue_date||"S/D"}</b></div>
            <div><span>Vencimiento</span><b>{selected.due_date||"S/D"}</b></div>
            <div><span>Tarifa</span><b>{selected.current_tariff_code||"S/D"} · {selected.voltage_level||m?.voltage_level||"S/D"}</b></div>
            <div><span>Importe</span><b>{money.format(Number(selected.total_amount||0))}</b></div>
            <div><span>IVA</span><b>{money.format(Number(selected.vat_amount||0))}</b></div>
            <div><span>Deuda anterior</span><b>{money.format(Number(selected.previous_debt_amount||0))}</b></div>
            <div><span>Reactiva</span><b>{nf.format(v.kvarh)} kvarh</b></div>
            <div><span>Dirección</span><b>{m?.sites?.address||"S/D"}</b></div>
          </div>
        </section>

        <section className="invoice-analysis-panel">
          <h3>Oportunidades de ahorro de esta factura</h3>
          <div className="invoice-analysis-saving-list">
            <div><span>Potencia contratada</span><b>{money.format(powerSaving)}</b><small>{excess>0?`${nf.format(excess)} kW sobrantes × tarifa de potencia + IVA 30%`:"Sin ahorro detectado"}</small></div>
            <div><span>Factor de potencia</span><b>{money.format(reactiveSaving)}</b><small>{reactiveSaving>0?"Penalización reactiva evitable + IVA 30%":"Sin penalización valorizada"}</small></div>
            <div><span>Encuadramiento tarifario</span><b>{money.format(tariffSaving)}</b><small>{tariffSaving>0?"Ahorro mensual simulado con IVA":"Sin ahorro tarifario valorizado"}</small></div>
            <div className="total"><span>Total mensual</span><b>{money.format(totalSaving)}</b><small>{money.format(totalSaving*12)} / año</small></div>
          </div>
        </section>
      </div>
<section className="invoice-analysis-panel">
        <h3>Conceptos facturados</h3>
        <div className="invoice-analysis-table-wrap"><table className="invoice-analysis-table">
          <thead><tr><th>Código</th><th>Descripción</th><th>Cantidad</th><th>Precio unitario</th><th>Importe neto</th></tr></thead>
          <tbody>{(selected.invoice_lines||[]).map((line,index)=><tr key={`${line.concept_code||"x"}-${index}`}>
            <td>{line.concept_code||"—"}</td><td>{line.description||"Sin descripción"}</td><td>{dec.format(Number(line.quantity||0))}</td><td>{money.format(Number(line.unit_price||0))}</td><td><b>{money.format(Number(line.net_amount||0))}</b></td>
          </tr>)}{!(selected.invoice_lines||[]).length&&<tr><td colSpan={5}>No hay conceptos discriminados en esta factura.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="invoice-analysis-panel">
        <h3>Mediciones registradas</h3>
        <div className="invoice-analysis-table-wrap"><table className="invoice-analysis-table">
          <thead><tr><th>Tipo</th><th>Medidor</th><th>kWh</th><th>kvarh</th><th>Demanda kW</th><th>FP</th><th>Recargo</th></tr></thead>
          <tbody>{(selected.invoice_measurements||[]).map((row,index)=><tr key={index}>
            <td>{row.measurement_type||"—"}</td><td>{row.meter_number||m?.meter_number||"—"}</td><td>{nf.format(Number(row.active_energy_kwh||0))}</td><td>{nf.format(Number(row.reactive_energy_kvarh||0))}</td><td>{nf.format(Number(row.demand_kw||row.registered_demand_peak_kw||0))}</td><td>{row.power_factor?Number(row.power_factor).toFixed(3):"—"}</td><td>{Number(row.reactive_surcharge_percent||0)}%</td>
          </tr>)}{!(selected.invoice_measurements||[]).length&&<tr><td colSpan={7}>No hay mediciones discriminadas en esta factura.</td></tr>}</tbody>
        </table></div>
      </section>
      <MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>

    </div>
  </div>
}
















