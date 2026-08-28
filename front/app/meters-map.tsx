"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";

const API="https://ahorro-energetico.onrender.com";

type Meter={
  id:string;tracking_code?:string;meter_number?:string;supply_number?:string;
  service_name?:string;current_tariff_code?:string;status?:string;
  contracted_kw_peak?:number;sites?:{name?:string;address?:string};
};
type Measurement={active_energy_kwh?:number;demand_kw?:number;registered_demand_peak_kw?:number;power_factor?:number};
type Invoice={
  id:string;meter_id:string;billing_period?:string;period_start:string;total_amount:number;
  contracted_kw_peak?:number;meters?:Meter;invoice_measurements?:Measurement[];
};
type Location={meter_id:string;latitude:number|string;longitude:number|string;valid_from?:string;source?:string};
type Props={
  session:Session;
  organizationId:string;
  meters:Meter[];
  invoices:Invoice[];
  onOpenMeter:(meterId:string)=>void;
};

declare global{interface Window{L?:any}}

const nf=new Intl.NumberFormat("es-AR",{maximumFractionDigits:0});
const money=new Intl.NumberFormat("es-AR",{style:"currency",currency:"ARS",maximumFractionDigits:0});

function periodOf(i:Invoice){return String(i.billing_period||i.period_start).slice(0,7)}
function metrics(i?:Invoice){
  if(!i)return{kwh:0,demand:0,pf:0,contracted:0,excess:0,amount:0};
  const ms=i.invoice_measurements||[];
  const kwh=ms.reduce((s,m)=>s+Number(m.active_energy_kwh||0),0);
  const demand=Math.max(0,...ms.map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));
  const pfs=ms.map(m=>Number(m.power_factor||0)).filter(v=>v>0);
  const pf=pfs.length?Math.min(...pfs):0;
  const contracted=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||0);
  return{kwh,demand,pf,contracted,excess:Math.max(0,contracted-demand),amount:Number(i.total_amount||0)};
}
function loadLeaflet():Promise<any>{
  if(typeof window==="undefined")return Promise.reject(new Error("Mapa no disponible"));
  if(window.L)return Promise.resolve(window.L);
  return new Promise((resolve,reject)=>{
    if(!document.getElementById("leaflet-css-global")){
      const link=document.createElement("link");
      link.id="leaflet-css-global";link.rel="stylesheet";
      link.href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
      document.head.appendChild(link);
    }
    const existing=document.getElementById("leaflet-js-global") as HTMLScriptElement|null;
    if(existing){
      if(window.L){resolve(window.L);return}
      existing.addEventListener("load",()=>resolve(window.L),{once:true});
      existing.addEventListener("error",()=>reject(new Error("No se pudo cargar Leaflet")),{once:true});
      return;
    }
    const script=document.createElement("script");
    script.id="leaflet-js-global";script.src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";script.async=true;
    script.onload=()=>resolve(window.L);script.onerror=()=>reject(new Error("No se pudo cargar Leaflet"));
    document.body.appendChild(script);
  });
}

export function MetersMap({session,organizationId,meters,invoices,onOpenMeter}:Props){
  const[locations,setLocations]=useState<Location[]>([]);
  const[search,setSearch]=useState("");
  const[filter,setFilter]=useState<"all"|"critical"|"opportunity"|"ok"|"unlocated">("all");
  const[selected,setSelected]=useState<string>("");
  const[error,setError]=useState("");
  const mapNode=useRef<HTMLDivElement|null>(null);
  const mapRef=useRef<any>(null);
  const markerRefs=useRef<Map<string,any>>(new Map());

  useEffect(()=>{
    fetch(`${API}/api/organizations/${organizationId}/meter-locations`,{
      headers:{Authorization:`Bearer ${session.access_token}`}
    }).then(async r=>{
      if(!r.ok)throw new Error(await r.text());
      return r.json();
    }).then(setLocations).catch(e=>setError(e instanceof Error?e.message:"No se pudieron cargar ubicaciones"));
  },[organizationId,session.access_token]);

  const latestByMeter=useMemo(()=>{
    const map=new Map<string,Invoice>();
    [...invoices].sort((a,b)=>periodOf(b).localeCompare(periodOf(a))).forEach(i=>{if(!map.has(i.meter_id))map.set(i.meter_id,i)});
    return map;
  },[invoices]);

  const locationByMeter=useMemo(()=>new Map(locations.map(l=>[l.meter_id,l])),[locations]);

  const rows=useMemo(()=>meters.map(m=>{
    const invoice=latestByMeter.get(m.id);
    const x=metrics(invoice);
    const located=locationByMeter.has(m.id);
    const critical=(x.pf>0&&x.pf<.95)||m.status==="inactive";
    const opportunity=x.excess>0&&!critical;
    const state: "critical"|"opportunity"|"ok"|"unlocated" = !located?"unlocated":critical?"critical":opportunity?"opportunity":"ok";
    return{meter:m,invoice,x,state,location:locationByMeter.get(m.id)};
  }),[meters,latestByMeter,locationByMeter]);

  const counts=useMemo(()=>({
    all:rows.length,
    located:rows.filter(r=>r.state!=="unlocated").length,
    critical:rows.filter(r=>r.state==="critical").length,
    opportunity:rows.filter(r=>r.state==="opportunity").length,
    ok:rows.filter(r=>r.state==="ok").length,
    unlocated:rows.filter(r=>r.state==="unlocated").length
  }),[rows]);

  const visible=useMemo(()=>rows.filter(r=>{
    const q=search.trim().toLowerCase();
    const text=[r.meter.service_name,r.meter.sites?.name,r.meter.sites?.address,r.meter.meter_number,r.meter.supply_number,r.meter.tracking_code].join(" ").toLowerCase();
    return(!q||text.includes(q))&&(filter==="all"||r.state===filter);
  }),[rows,search,filter]);

  useEffect(()=>{
    let cancelled=false;
    loadLeaflet().then(L=>{
      if(cancelled||!mapNode.current)return;
      if(!mapRef.current){
        mapRef.current=L.map(mapNode.current,{zoomControl:true}).setView([-37.3895,-68.9250],13);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:20,attribution:"&copy; OpenStreetMap"}).addTo(mapRef.current);
      }
      markerRefs.current.forEach(marker=>marker.remove());
      markerRefs.current.clear();

      const bounds:any[]=[];
      for(const row of visible){
        if(!row.location)continue;
        const lat=Number(row.location.latitude),lng=Number(row.location.longitude);
        if(!Number.isFinite(lat)||!Number.isFinite(lng))continue;

        const color=row.state==="critical"?"#c94b40":row.state==="opportunity"?"#d89520":"#168d60";
        const icon=L.divIcon({
          className:"meter-map-marker-shell",
          html:`<div class="meter-map-marker ${row.state}" style="--marker:${color}"><span>⚡</span></div>`,
          iconSize:[34,42],iconAnchor:[17,38],popupAnchor:[0,-34]
        });
        const name=row.meter.service_name||row.meter.sites?.name||`Medidor ${row.meter.meter_number||"S/D"}`;
        const popup=`
          <div class="meter-map-popup">
            <b>${name}</b>
            <span>Medidor ${row.meter.meter_number||"S/D"} · Suministro ${row.meter.supply_number||"S/D"}</span>
            <div><i>Consumo</i><strong>${nf.format(row.x.kwh)} kWh</strong></div>
            <div><i>Demanda</i><strong>${nf.format(row.x.demand)} kW</strong></div>
            <div><i>Pot. contratada</i><strong>${nf.format(row.x.contracted)} kW</strong></div>
            <div><i>Cos φ</i><strong>${row.x.pf?row.x.pf.toFixed(3):"S/D"}</strong></div>
            <small>${row.invoice?`Última factura ${periodOf(row.invoice)}`:"Sin factura cargada"}</small>
          </div>`;
        const marker=L.marker([lat,lng],{icon}).addTo(mapRef.current).bindPopup(popup);
        marker.on("click",()=>setSelected(row.meter.id));
        markerRefs.current.set(row.meter.id,marker);
        bounds.push([lat,lng]);
      }
      if(bounds.length>1)mapRef.current.fitBounds(bounds,{padding:[35,35],maxZoom:16});
      else if(bounds.length===1)mapRef.current.setView(bounds[0],16);
      setTimeout(()=>mapRef.current?.invalidateSize(),100);
    }).catch(e=>setError(e instanceof Error?e.message:"No se pudo cargar el mapa"));
    return()=>{cancelled=true};
  },[visible]);

  useEffect(()=>{
    if(!selected)return;
    const marker=markerRefs.current.get(selected);
    if(marker){marker.openPopup();const ll=marker.getLatLng();mapRef.current?.panTo(ll)}
  },[selected]);

  const selectedRow=rows.find(r=>r.meter.id===selected);

  return <div className="meters-real-module">
    <div className="meters-map-kpis">
      <article><span>Medidores</span><b>{counts.all}</b><small>total registrados</small></article>
      <article className="located"><span>Ubicados</span><b>{counts.located}</b><small>con coordenadas reales</small></article>
      <article className="critical"><span>Críticos</span><b>{counts.critical}</b><small>FP bajo / posible baja</small></article>
      <article className="opportunity"><span>Oportunidad</span><b>{counts.opportunity}</b><small>potencia sobrante</small></article>
      <article className="unlocated"><span>Sin ubicación</span><b>{counts.unlocated}</b><small>pendientes de georreferenciar</small></article>
    </div>

    <div className="meters-map-toolbar">
      <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Buscar servicio, medidor, suministro o dirección"/>
      <div className="meters-map-filters">
        <button className={filter==="all"?"active":""} onClick={()=>setFilter("all")}>Todos</button>
        <button className={filter==="critical"?"active critical":""} onClick={()=>setFilter("critical")}>Críticos</button>
        <button className={filter==="opportunity"?"active opportunity":""} onClick={()=>setFilter("opportunity")}>Oportunidades</button>
        <button className={filter==="ok"?"active ok":""} onClick={()=>setFilter("ok")}>Correctos</button>
        <button className={filter==="unlocated"?"active unlocated":""} onClick={()=>setFilter("unlocated")}>Sin ubicación</button>
      </div>
    </div>

    <div className="meters-map-workspace">
      <section className="panel meters-leaflet-panel">
        <div ref={mapNode} className="meters-leaflet-map"/>
        <div className="meters-map-legend">
          <span><i className="red"/>Crítico</span>
          <span><i className="amber"/>Oportunidad</span>
          <span><i className="green"/>Correcto</span>
        </div>
        {error&&<div className="meters-map-error">{error}</div>}
      </section>

      <aside className="panel meters-real-list">
        <div className="meters-real-list-head">
          <div><h3>Medidores</h3><p>{visible.length} resultados</p></div>
        </div>
        <div className="meters-real-list-body">
          {visible.map(r=><button key={r.meter.id} className={`meters-real-row ${r.state} ${selected===r.meter.id?"selected":""}`} onClick={()=>setSelected(r.meter.id)}>
            <i/>
            <div>
              <b>{r.meter.service_name||r.meter.sites?.name||"Servicio sin nombre"}</b>
              <span>Medidor {r.meter.meter_number||"S/D"} · Sum. {r.meter.supply_number||"S/D"}</span>
              <small>{r.location?r.meter.sites?.address||"Ubicación cargada":"Sin coordenadas"}</small>
            </div>
            <em>{r.x.pf?`FP ${r.x.pf.toFixed(2)}`:r.state==="unlocated"?"GPS":"—"}</em>
          </button>)}
        </div>
      </aside>
    </div>

    {selectedRow&&<section className="panel meters-selected-card">
      <div>
        <span>MEDIDOR SELECCIONADO</span>
        <h3>{selectedRow.meter.service_name||selectedRow.meter.sites?.name||"Servicio sin nombre"}</h3>
        <p>{selectedRow.meter.tracking_code} · Medidor {selectedRow.meter.meter_number||"S/D"} · Suministro {selectedRow.meter.supply_number||"S/D"}</p>
      </div>
      <div className="meters-selected-stats">
        <div><span>Consumo</span><b>{nf.format(selectedRow.x.kwh)} kWh</b></div>
        <div><span>Demanda</span><b>{nf.format(selectedRow.x.demand)} kW</b></div>
        <div><span>Contratada</span><b>{nf.format(selectedRow.x.contracted)} kW</b></div>
        <div><span>Factor potencia</span><b>{selectedRow.x.pf?selectedRow.x.pf.toFixed(3):"S/D"}</b></div>
        <div><span>Última factura</span><b>{selectedRow.invoice?periodOf(selectedRow.invoice):"S/D"}</b></div>
        <div><span>Importe</span><b>{money.format(selectedRow.x.amount)}</b></div>
      </div>
      <button className="meters-open-analysis" onClick={()=>onOpenMeter(selectedRow.meter.id)} disabled={!selectedRow.invoice}>Abrir análisis individual →</button>
    </section>}
  </div>
}