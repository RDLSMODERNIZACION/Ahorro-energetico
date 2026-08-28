$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - MAPA MEDIDORES REAL V43" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$root=$null
foreach($c in @($here,(Split-Path -Parent $here))){
  if((Test-Path (Join-Path $c "front\app\page.tsx")) -and
     (Test-Path (Join-Path $c "back\app\routers\catalog.py"))){$root=$c;break}
}
if(-not $root){throw "No encontre front y back del proyecto."}

$front=Join-Path $root "front"
$back=Join-Path $root "back"
$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"
$catalogPath=Join-Path $back "app\routers\catalog.py"
$mapPath=Join-Path $front "app\meters-map.tsx"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_mapa_medidores_real_v43_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force
Copy-Item $catalogPath (Join-Path $backup "catalog.py") -Force
if(Test-Path $mapPath){Copy-Item $mapPath (Join-Path $backup "meters-map.tsx") -Force}

# ================================================================
# BACKEND: endpoint de ubicaciones vigentes
# ================================================================
$catalog=Get-Content $catalogPath -Raw
if($catalog -notmatch '/organizations/\{organization_id\}/meter-locations'){
$endpoint=@'

@router.get("/organizations/{organization_id}/meter-locations")
def list_meter_locations(organization_id: str, user: CurrentUser = Depends(current_user)):
    require_org(user.id, organization_id)
    db = admin_db()
    meters = db.table("meters").select("id").eq("organization_id", organization_id).execute().data
    meter_ids = [row["id"] for row in meters]
    if not meter_ids:
        return []
    rows = (
        db.table("meter_locations")
        .select("meter_id,latitude,longitude,valid_from,source")
        .in_("meter_id", meter_ids)
        .is_("valid_to", "null")
        .order("valid_from", desc=True)
        .execute()
        .data
    )
    latest = {}
    for row in rows:
        latest.setdefault(row["meter_id"], row)
    return list(latest.values())

'@
  $anchor='@router.get("/meters/{meter_id}/location")'
  $idx=$catalog.IndexOf($anchor)
  if($idx -lt 0){throw "No encontre endpoint location en catalog.py."}
  $catalog=$catalog.Insert($idx,$endpoint)
}
Set-Content $catalogPath $catalog -Encoding UTF8

# ================================================================
# NUEVO COMPONENTE MAPA REAL
# ================================================================
$component=@'
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
'@
[System.IO.File]::WriteAllText($mapPath,$component,(New-Object System.Text.UTF8Encoding($false)))

# ================================================================
# PAGE: importar y reemplazar mapa viejo
# ================================================================
$page=Get-Content $pagePath -Raw
if($page -notmatch 'from "\./meters-map"'){
  $page=$page.Replace('import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";','import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";'+"`r`n"+'import { MetersMap } from "./meters-map";')
}

$start=$page.IndexOf('{tab==="map"&&<div className="map-layout">')
$endMarker='  </section>{toast&&<div className="toast">'
$end=$page.IndexOf($endMarker)
if($start -lt 0 -or $end -lt 0 -or $end -le $start){throw "No pude localizar el bloque del mapa viejo."}

$newMap='{tab==="map"&&session&&orgId&&<MetersMap session={session} organizationId={orgId} meters={meters} invoices={invoices} onOpenMeter={openMeterById}/>}'+"`r`n"
$page=$page.Substring(0,$start)+$newMap+$page.Substring($end)
Set-Content $pagePath $page -Encoding UTF8

# ================================================================
# CSS
# ================================================================
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === MAPA MEDIDORES REAL V43 START === \*/.*?/\* === MAPA MEDIDORES REAL V43 END === \*/','')
$css += @'

/* === MAPA MEDIDORES REAL V43 START === */
.meters-real-module{display:flex;flex-direction:column;gap:14px}
.meters-map-kpis{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px}
.meters-map-kpis article{background:#fff;border:1px solid #dfe8e3;border-radius:14px;padding:15px 17px;display:flex;flex-direction:column;gap:5px}
.meters-map-kpis span{font-size:10px;font-weight:750;color:#73877d;text-transform:uppercase;letter-spacing:.04em}
.meters-map-kpis b{font-size:25px;color:#10241b}
.meters-map-kpis small{font-size:10px;color:#87968f}
.meters-map-kpis .critical{background:#fff8f6;border-color:#f0d6d0}
.meters-map-kpis .critical b{color:#b84538}
.meters-map-kpis .opportunity{background:#fffaf0;border-color:#eedfbd}
.meters-map-kpis .opportunity b{color:#b37814}
.meters-map-kpis .located{background:#f2fbf6;border-color:#cfe9d8}
.meters-map-kpis .located b{color:#137e53}
.meters-map-kpis .unlocated b{color:#718078}

.meters-map-toolbar{display:flex;gap:12px;align-items:center;background:#fff;border:1px solid #dfe8e3;border-radius:14px;padding:11px 13px}
.meters-map-toolbar input{flex:1;min-width:260px;border:1px solid #d9e4de;border-radius:10px;padding:11px 13px;outline:none}
.meters-map-filters{display:flex;gap:7px;flex-wrap:wrap}
.meters-map-filters button{border:1px solid #d9e4de;background:#fff;border-radius:999px;padding:8px 11px;font-size:11px;font-weight:750;cursor:pointer}
.meters-map-filters button.active{background:#173f32;color:#fff;border-color:#173f32}
.meters-map-filters button.active.critical{background:#b84538;border-color:#b84538}
.meters-map-filters button.active.opportunity{background:#b67d1d;border-color:#b67d1d}
.meters-map-filters button.active.ok{background:#168d60;border-color:#168d60}
.meters-map-filters button.active.unlocated{background:#78877f;border-color:#78877f}

.meters-map-workspace{display:grid;grid-template-columns:minmax(0,1fr) 360px;gap:14px;min-height:620px}
.meters-leaflet-panel{position:relative;overflow:hidden;padding:0!important}
.meters-leaflet-map{width:100%;height:620px;background:#edf3ef}
.meters-map-legend{position:absolute;z-index:500;left:15px;bottom:15px;background:rgba(255,255,255,.95);border:1px solid #dbe5df;border-radius:11px;padding:9px 12px;display:flex;gap:13px;font-size:10px;font-weight:700;box-shadow:0 6px 20px rgba(28,55,43,.12)}
.meters-map-legend span{display:flex;align-items:center;gap:6px}
.meters-map-legend i{width:9px;height:9px;border-radius:50%}
.meters-map-legend .red{background:#c94b40}.meters-map-legend .amber{background:#d89520}.meters-map-legend .green{background:#168d60}
.meters-map-error{position:absolute;top:15px;left:50%;transform:translateX(-50%);z-index:600;background:#fff0ed;color:#a6382e;border:1px solid #edc7c0;border-radius:9px;padding:9px 12px;font-size:11px;font-weight:700}

.meter-map-marker-shell{background:transparent!important;border:0!important}
.meter-map-marker{width:34px;height:34px;border-radius:50% 50% 50% 8px;transform:rotate(-45deg);background:var(--marker);border:3px solid white;box-shadow:0 4px 12px rgba(20,44,34,.25);display:flex;align-items:center;justify-content:center}
.meter-map-marker span{transform:rotate(45deg);font-size:14px}
.meter-map-marker.critical{animation:meterPulse 1.8s infinite}
@keyframes meterPulse{0%,100%{box-shadow:0 0 0 0 rgba(201,75,64,.35),0 4px 12px rgba(20,44,34,.25)}50%{box-shadow:0 0 0 8px rgba(201,75,64,0),0 4px 12px rgba(20,44,34,.25)}}

.meter-map-popup{min-width:210px;display:grid;grid-template-columns:1fr 1fr;gap:6px 12px}
.meter-map-popup>b,.meter-map-popup>span,.meter-map-popup>small{grid-column:1/-1}
.meter-map-popup>b{font-size:13px;color:#153b2f}
.meter-map-popup>span{font-size:10px;color:#718078;margin-bottom:4px}
.meter-map-popup div{display:flex;flex-direction:column}
.meter-map-popup i{font-size:9px;color:#87948e;font-style:normal}
.meter-map-popup strong{font-size:11px}
.meter-map-popup small{font-size:9px;color:#87948e;border-top:1px solid #edf1ef;padding-top:6px;margin-top:3px}

.meters-real-list{padding:0!important;overflow:hidden;display:flex;flex-direction:column}
.meters-real-list-head{padding:15px 16px;border-bottom:1px solid #e2e9e5}
.meters-real-list-head h3{margin:0;font-size:16px}.meters-real-list-head p{margin:3px 0 0;font-size:10px;color:#819087}
.meters-real-list-body{overflow:auto;max-height:570px}
.meters-real-row{width:100%;border:0;border-bottom:1px solid #edf1ef;background:#fff;padding:12px 13px;display:grid;grid-template-columns:10px 1fr auto;gap:10px;text-align:left;cursor:pointer;align-items:center}
.meters-real-row:hover,.meters-real-row.selected{background:#f3f8f5}
.meters-real-row>i{width:9px;height:9px;border-radius:50%;background:#168d60}
.meters-real-row.critical>i{background:#c94b40}.meters-real-row.opportunity>i{background:#d89520}.meters-real-row.unlocated>i{background:#9aa7a0}
.meters-real-row div{display:flex;flex-direction:column;gap:2px;min-width:0}
.meters-real-row b{font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meters-real-row span,.meters-real-row small{font-size:9px;color:#78877f;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meters-real-row em{font-size:9px;font-style:normal;font-weight:800;color:#65746c}

.meters-selected-card{display:grid;grid-template-columns:minmax(250px,1fr) 2fr auto;gap:18px;align-items:center;padding:17px 19px}
.meters-selected-card>div:first-child span{font-size:9px;font-weight:800;color:#7a8d83;letter-spacing:.06em}
.meters-selected-card h3{margin:4px 0;font-size:18px}.meters-selected-card p{margin:0;font-size:10px;color:#75867d}
.meters-selected-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:9px}
.meters-selected-stats div{background:#f7faf8;border-radius:9px;padding:8px 10px}
.meters-selected-stats span{display:block;font-size:8px;color:#83928a;text-transform:uppercase;font-weight:700}
.meters-selected-stats b{font-size:11px}
.meters-open-analysis{border:0;border-radius:10px;background:#158d5f;color:#fff;padding:12px 14px;font-weight:800;cursor:pointer;white-space:nowrap}
.meters-open-analysis:disabled{opacity:.4;cursor:not-allowed}

@media(max-width:1200px){
  .meters-map-kpis{grid-template-columns:repeat(3,1fr)}
  .meters-map-workspace{grid-template-columns:1fr}
  .meters-real-list-body{max-height:340px}
  .meters-selected-card{grid-template-columns:1fr}
}
@media(max-width:720px){
  .meters-map-kpis{grid-template-columns:repeat(2,1fr)}
  .meters-map-toolbar{flex-direction:column;align-items:stretch}
  .meters-selected-stats{grid-template-columns:repeat(2,1fr)}
}
/* === MAPA MEDIDORES REAL V43 END === */
'@
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @((Join-Path $front ".next"),(Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$checkPage=Get-Content $pagePath -Raw
$checkCatalog=Get-Content $catalogPath -Raw
if($checkPage -notmatch 'MetersMap' -or $checkCatalog -notmatch 'meter-locations'){throw "La verificacion final fallo."}

Write-Host ""
Write-Host "V43 aplicado correctamente." -ForegroundColor Green
Write-Host "Mapa real con Leaflet + ubicaciones guardadas + estados por color." -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Read-Host "ENTER para cerrar"
