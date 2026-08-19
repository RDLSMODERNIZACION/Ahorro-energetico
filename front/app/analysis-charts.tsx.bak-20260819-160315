"use client";

import { useEffect, useMemo, useState } from "react";

type Measurement={active_energy_kwh?:number;demand_kw?:number;registered_demand_peak_kw?:number};
type Line={concept_code?:string;quantity?:number;unit_price?:number;net_amount?:number};
type Meter={id:string;meter_number?:string;supply_number?:string;nis?:string;tracking_code?:string;service_name?:string;sites?:{name?:string}};
type Invoice={id:string;meter_id:string;billing_period?:string;period_start:string;total_amount:number;contracted_kw_peak?:number;meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:Line[]};
type TariffSaving={meter_id:string;billing_period:string;monthly_saving_with_vat:number};
type Metric="kwh"|"amount"|"demand"|"saving";
type Point={period:string;kwh:number;amount:number;demand:number;saving:number;invoices:number};

const nf=new Intl.NumberFormat("es-AR",{maximumFractionDigits:0});
const money=new Intl.NumberFormat("es-AR",{style:"currency",currency:"ARS",maximumFractionDigits:0});
const metricMeta:Record<Metric,{label:string;unit:string;format:(value:number)=>string}>={
  kwh:{label:"Consumo",unit:"kWh",format:value=>`${nf.format(value)} kWh`},
  amount:{label:"Importe facturado",unit:"$",format:value=>money.format(value)},
  demand:{label:"Demanda máxima",unit:"kW",format:value=>`${nf.format(value)} kW`},
  saving:{label:"Ahorro estimado",unit:"$",format:value=>money.format(value)},
};

function periodOf(invoice:Invoice){return String(invoice.billing_period||invoice.period_start).slice(0,7)}
function invoiceMetrics(invoice:Invoice,tariffSavings:TariffSaving[]){
  const measurements=invoice.invoice_measurements||[];
  const kwh=measurements.reduce((sum,row)=>sum+Number(row.active_energy_kwh||0),0);
  const demand=Math.max(0,...measurements.map(row=>Number(row.demand_kw||row.registered_demand_peak_kw||0)));
  const powerLines=(invoice.invoice_lines||[]).filter(row=>row.concept_code==="DEM"||row.concept_code==="DEP");
  const contracted=Number(invoice.contracted_kw_peak||Math.max(0,...powerLines.map(row=>Number(row.quantity||0))));
  const unitPrice=Math.max(0,...powerLines.map(row=>Number(row.unit_price||0)));
  const powerSaving=Math.max(0,contracted-demand)*unitPrice*1.30;
  const reactiveSaving=(invoice.invoice_lines||[]).filter(row=>row.concept_code==="COS").reduce((sum,row)=>sum+Math.max(0,Number(row.net_amount||0)),0)*1.30;
  const tariffSaving=tariffSavings.find(row=>row.meter_id===invoice.meter_id&&String(row.billing_period).slice(0,7)===periodOf(invoice));
  return{kwh,demand,amount:Number(invoice.total_amount||0),saving:powerSaving+reactiveSaving+Number(tariffSaving?.monthly_saving_with_vat||0)};
}
function monthRange(invoices:Invoice[]){
  const latest=[...invoices.map(periodOf).filter(Boolean)].sort().at(-1)||new Date().toISOString().slice(0,7);
  const [year,month]=latest.split("-").map(Number);
  return Array.from({length:24},(_,index)=>{const date=new Date(Date.UTC(year,month-1-(23-index),1));return date.toISOString().slice(0,7)});
}
function aggregate(invoices:Invoice[],months:string[],tariffSavings:TariffSaving[]):Point[]{
  return months.map(period=>{const rows=invoices.filter(invoice=>periodOf(invoice)===period);return rows.reduce<Point>((point,invoice)=>{const values=invoiceMetrics(invoice,tariffSavings);point.kwh+=values.kwh;point.amount+=values.amount;point.demand+=values.demand;point.saving+=values.saving;point.invoices+=1;return point},{period,kwh:0,amount:0,demand:0,saving:0,invoices:0})});
}
function labelPeriod(period:string){const[y,m]=period.split("-").map(Number);return new Date(y,m-1,1).toLocaleString("es-AR",{month:"short",year:"2-digit"}).replace(".","")}

function TrendChart({data,metric}:{data:Point[];metric:Metric}){
  const width=1200,height=310,left=62,right=18,top=22,bottom=50,plotW=width-left-right,plotH=height-top-bottom;
  const values=data.map(row=>row[metric]);const max=Math.max(1,...values)*1.08;
  const barSlot=plotW/Math.max(1,data.length),barWidth=Math.max(8,barSlot*.58);
  return <div className="history-chart-wrap"><svg className="history-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${metricMeta[metric].label} mensual`}>
    {[0,.25,.5,.75,1].map(step=>{const y=top+plotH*(1-step);return <g key={step}><line x1={left} x2={width-right} y1={y} y2={y}/><text x={left-10} y={y+4} textAnchor="end">{nf.format(max*step)}</text></g>})}
    {data.map((row,index)=>{const value=row[metric],x=left+index*barSlot+(barSlot-barWidth)/2,y=top+plotH-(value/max)*plotH;return <g className={row.invoices?"history-bar":"history-bar missing"} key={row.period}><rect x={x} y={y} width={barWidth} height={Math.max(1,top+plotH-y)} rx="4"><title>{labelPeriod(row.period)} · {metricMeta[metric].format(value)} · {row.invoices} factura(s)</title></rect>{(index%3===0||index===data.length-1)&&<text className="month-label" x={x+barWidth/2} y={height-23} textAnchor="middle">{labelPeriod(row.period)}</text>}</g>})}
  </svg></div>
}

function MetricButtons({value,onChange}:{value:Metric;onChange:(metric:Metric)=>void}){return <div className="metric-buttons">{(Object.keys(metricMeta) as Metric[]).map(metric=><button key={metric} className={value===metric?"active":""} onClick={()=>onChange(metric)}>{metricMeta[metric].label}</button>)}</div>}

function meterLabel(meter:Meter){
  const identifier=meter.meter_number||meter.supply_number||meter.nis||meter.tracking_code||"Sin identificación";
  const service=meter.service_name||meter.sites?.name||"Servicio sin nombre";
  return `${identifier} · ${service}`;
}

function MeterSearch({meters,value,onChange}:{meters:Meter[];value:string;onChange:(id:string)=>void}){
  const selected=meters.find(row=>row.id===value);
  const[query,setQuery]=useState(selected?meterLabel(selected):"");
  const[open,setOpen]=useState(false);
  useEffect(()=>{if(selected)setQuery(meterLabel(selected))},[selected?.id]);
  const normalized=query.trim().toLocaleLowerCase("es");
  const matches=useMemo(()=>meters.filter(row=>{
    if(!normalized)return true;
    return [row.meter_number,row.supply_number,row.nis,row.tracking_code,row.service_name,row.sites?.name]
      .filter(Boolean).join(" ").toLocaleLowerCase("es").includes(normalized);
  }).slice(0,10),[meters,normalized]);
  function selectMeter(meter:Meter){onChange(meter.id);setQuery(meterLabel(meter));setOpen(false)}
  return <label className="meter-search-label">Buscar medidor o suministro
    <div className="meter-search">
      <span aria-hidden="true">⌕</span>
      <input value={query} onFocus={event=>{event.currentTarget.select();setOpen(true)}} onChange={event=>{setQuery(event.target.value);setOpen(true)}} onKeyDown={event=>{if(event.key==="Enter"&&matches[0]){event.preventDefault();selectMeter(matches[0])}if(event.key==="Escape")setOpen(false)}} onBlur={()=>setTimeout(()=>setOpen(false),150)} placeholder="Escribí medidor, suministro o servicio" role="combobox" aria-expanded={open} aria-autocomplete="list"/>
      {query&&<button type="button" aria-label="Limpiar búsqueda" onMouseDown={event=>event.preventDefault()} onClick={()=>{setQuery("");setOpen(true)}}>×</button>}
      {open&&<div className="meter-search-results" role="listbox">
        {matches.map(row=><button type="button" role="option" aria-selected={row.id===value} className={row.id===value?"active":""} key={row.id} onMouseDown={event=>event.preventDefault()} onClick={()=>selectMeter(row)}><b>{row.meter_number||"Sin medidor"}</b><span>{row.service_name||row.sites?.name||"Servicio sin nombre"}</span><small>Suministro {row.supply_number||row.nis||"S/D"} · {row.tracking_code||"Sin ID"}</small></button>)}
        {!matches.length&&<p>No encontramos coincidencias.</p>}
      </div>}
    </div>
  </label>
}

export function HistoricalAnalysis({invoices,meters,tariffSavings}:{invoices:Invoice[];meters:Meter[];tariffSavings:TariffSaving[]}){
  const[globalMetric,setGlobalMetric]=useState<Metric>("kwh"),[meterMetric,setMeterMetric]=useState<Metric>("kwh"),[selectedMeter,setSelectedMeter]=useState("");
  const months=useMemo(()=>monthRange(invoices),[invoices]);
  const globalData=useMemo(()=>aggregate(invoices,months,tariffSavings),[invoices,months,tariffSavings]);
  const meterId=selectedMeter||meters[0]?.id||"";
  const meter=meters.find(row=>row.id===meterId);
  const meterData=useMemo(()=>aggregate(invoices.filter(invoice=>invoice.meter_id===meterId),months,tariffSavings),[invoices,meterId,months,tariffSavings]);
  const latest=globalData.at(-1),previous=globalData.at(-2),latestValue=Number(latest?.[globalMetric]||0),previousValue=Number(previous?.[globalMetric]||0),variation=previousValue?((latestValue-previousValue)/previousValue)*100:0;
  const meterRows=invoices.filter(invoice=>invoice.meter_id===meterId),meterTotal=meterData.reduce((sum,row)=>sum+row[meterMetric],0),meterPeak=Math.max(0,...meterData.map(row=>row[meterMetric]));
  return <div className="historical-analysis">
    <section className="panel history-panel"><div className="history-head"><div><h2>Evolución global mensual</h2><p>Últimos 24 meses hasta el período más reciente cargado · todos los medidores</p></div><MetricButtons value={globalMetric} onChange={setGlobalMetric}/></div>
      <div className="history-kpis"><article><span>Último mes</span><b>{metricMeta[globalMetric].format(latestValue)}</b><small>{latest?labelPeriod(latest.period):"Sin datos"}</small></article><article><span>Variación mensual</span><b className={variation>0?"up":"down"}>{previousValue?`${variation>=0?"+":""}${variation.toFixed(1)}%`:"S/D"}</b><small>contra el mes anterior</small></article><article><span>Facturas incluidas</span><b>{latest?.invoices||0}</b><small>en el último período</small></article><article><span>Período analizado</span><b>24 meses</b><small>{months[0]} a {months.at(-1)}</small></article></div>
      <TrendChart data={globalData} metric={globalMetric}/><div className="chart-note"><i/> Mes sin factura cargada <span>Pasá el cursor sobre cada barra para ver el valor exacto.</span></div>
    </section>
    <section className="panel history-panel meter-history"><div className="history-head"><div><h2>Análisis por medidor</h2><p>Buscá por medidor, suministro o nombre del servicio</p></div><MeterSearch meters={meters} value={meterId} onChange={setSelectedMeter}/></div>
      <div className="meter-analysis-title"><div><b>{meter?.service_name||meter?.sites?.name||"Servicio sin nombre"}</b><small>{meter?.tracking_code} · Medidor {meter?.meter_number}</small></div><MetricButtons value={meterMetric} onChange={setMeterMetric}/></div>
      <div className="history-kpis compact"><article><span>Total del período</span><b>{metricMeta[meterMetric].format(meterTotal)}</b></article><article><span>Máximo mensual</span><b>{metricMeta[meterMetric].format(meterPeak)}</b></article><article><span>Meses con factura</span><b>{new Set(meterRows.map(periodOf)).size} / 24</b></article><article><span>Último dato</span><b>{[...meterRows.map(periodOf)].sort().at(-1)||"Sin factura"}</b></article></div>
      <TrendChart data={meterData} metric={meterMetric}/>
    </section>
  </div>;
}
