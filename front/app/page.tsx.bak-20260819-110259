"use client";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "./lib/supabase";

const API = (import.meta.env.VITE_API_URL as string) || "https://ahorro-energetico.onrender.com";
const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
type Organization = { organization_id:string; role:string; organizations:{id:string;name:string} };
type Meter = { id:string;tracking_code:string;meter_number:string;nis?:string;current_tariff_code?:string;voltage_level?:string;contracted_kw_peak?:number;sites?:{name:string;address?:string} };
type Measurement = {active_energy_kwh?:number;reactive_energy_kvarh?:number;demand_kw?:number};
type Invoice = {id:string;meter_id:string;period_start:string;period_end:string;total_amount:number;current_tariff_code?:string;contracted_kw_peak?:number;meters?:{meter_number:string;tracking_code?:string;sites?:{name:string}};invoice_measurements?:Measurement[]};
type Missing = {id:string;expected_period:string;message:string;status:string;meters?:{tracking_code:string;meter_number:string;sites?:{name:string}}};
type Opportunity = {id:string;title:string;priority:string;estimated_annual_saving:number;estimated_investment:number;status:string;meters?:{meter_number:string;sites?:{name:string}}};

async function api<T>(path:string, session:Session, init?:RequestInit):Promise<T>{
  const response=await fetch(`${API}${path}`,{...init,headers:{Authorization:`Bearer ${session.access_token}`,...(init?.body instanceof FormData?{}:{"Content-Type":"application/json"}),...(init?.headers||{})}});
  if(!response.ok){const body=await response.text();throw new Error(body||`Error ${response.status}`)}
  if(response.status===204)return undefined as T;return response.json();
}

export default function Home(){
  const[session,setSession]=useState<Session|null>(null),[authReady,setAuthReady]=useState(false);
  const[email,setEmail]=useState(""),[password,setPassword]=useState(""),[loginError,setLoginError]=useState(""),[loginBusy,setLoginBusy]=useState(false);
  const[organization,setOrganization]=useState<Organization|null>(null),[meters,setMeters]=useState<Meter[]>([]),[invoices,setInvoices]=useState<Invoice[]>([]),[missing,setMissing]=useState<Missing[]>([]),[opportunities,setOpportunities]=useState<Opportunity[]>([]);
  const[tab,setTab]=useState<"dashboard"|"invoices"|"tariffs"|"map">("dashboard"),[busy,setBusy]=useState(false),[toast,setToast]=useState(""),[selectedMeter,setSelectedMeter]=useState("");
  const fileRef=useRef<HTMLInputElement>(null);

  useEffect(()=>{supabase.auth.getSession().then(({data})=>{setSession(data.session);setAuthReady(true)});const{data}=supabase.auth.onAuthStateChange((_e,s)=>setSession(s));return()=>data.subscription.unsubscribe()},[]);
  const orgId=organization?.organization_id;
  const load=useCallback(async(s:Session,org?:string)=>{
    try{
      let target=org;
      if(!target){const orgs=await api<Organization[]>("/api/organizations",s);if(!orgs.length)throw new Error("Tu usuario todavía no está asociado a la Municipalidad");setOrganization(orgs[0]);target=orgs[0].organization_id}
      const [m,i,o]=await Promise.all([api<Meter[]>(`/api/organizations/${target}/meters`,s),api<Invoice[]>(`/api/organizations/${target}/invoices?limit=500`,s),api<Opportunity[]>(`/api/organizations/${target}/opportunities`,s).catch(()=>[])]);
      setMeters(m);setInvoices(i);setOpportunities(o);if(!selectedMeter&&m[0])setSelectedMeter(m[0].id);
      setMissing(await api<Missing[]>(`/api/organizations/${target}/missing-invoices`,s).catch(()=>[]));
    }catch(e){setToast(e instanceof Error?e.message:"No se pudieron cargar los datos")}
  },[selectedMeter]);
  useEffect(()=>{if(session)load(session,orgId)},[session,orgId,load]);

  async function login(e:FormEvent){e.preventDefault();setLoginBusy(true);setLoginError("");const{error}=await supabase.auth.signInWithPassword({email,password});if(error)setLoginError(error.message);setLoginBusy(false)}
  async function upload(file?:File){if(!file||!session||!orgId)return;setBusy(true);try{const form=new FormData();form.append("organization_id",orgId);form.append("file",file);const result=await api<{imported:number;missing_count:number;duplicate:boolean}>("/api/imports/invoices",session,{method:"POST",body:form});setToast(result.duplicate?"Este archivo ya había sido cargado":`${result.imported} facturas importadas · ${result.missing_count} faltantes`);await load(session,orgId)}catch(e){setToast(e instanceof Error?e.message:"No se pudo importar") }finally{setBusy(false);setTimeout(()=>setToast(""),5000)}}
  async function analyze(){if(!session||!orgId)return;setBusy(true);try{const r=await api<{opportunities_created:number}>(`/api/organizations/${orgId}/analysis/run`,session,{method:"POST"});setToast(`${r.opportunities_created} oportunidades detectadas`);await load(session,orgId)}catch(e){setToast(e instanceof Error?e.message:"No se pudo analizar")}finally{setBusy(false)}}

  const total=invoices.reduce((s,x)=>s+Number(x.total_amount||0),0),kwh=invoices.reduce((s,x)=>s+(x.invoice_measurements||[]).reduce((a,m)=>a+Number(m.active_energy_kwh||0),0),0),annualSaving=opportunities.filter(x=>x.status!=="dismissed").reduce((s,x)=>s+Number(x.estimated_annual_saving||0),0);
  const periods=[...new Set(invoices.map(x=>x.period_start.slice(0,7)))].sort().reverse();
  const markerData=useMemo(()=>meters.map((m,index)=>({...m,x:14+(index*19)%72,y:18+(index*27)%65})),[meters]);

  if(!authReady)return <main className="loading-page">Cargando…</main>;
  if(!session)return <main className="login-page"><section className="login-card"><div className="login-brand"><span>M</span><div><b>GESTIÓN</b><small>ENERGÉTICA MUNICIPAL</small></div></div><h1>Ingresar al sistema</h1><p>Facturación EPEN y oportunidades de ahorro</p><form onSubmit={login}><label>Correo electrónico<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required/></label>{loginError&&<div className="login-error">{loginError}</div>}<button disabled={loginBusy}>{loginBusy?"Ingresando…":"Ingresar"}</button></form><small>El usuario debe estar creado en Supabase Authentication.</small></section></main>;

  return <main className="shell"><aside className="side"><div className="brand"><span>M</span><div><b>GESTIÓN</b><small>ENERGÉTICA MUNICIPAL</small></div></div><nav><button className={tab==="dashboard"?"active":""} onClick={()=>setTab("dashboard")}>⌁ <span>Resumen</span></button><button className={tab==="invoices"?"active":""} onClick={()=>setTab("invoices")}>▤ <span>Facturas</span></button><button className={tab==="tariffs"?"active":""} onClick={()=>setTab("tariffs")}>↗ <span>Ahorros</span></button><button className={tab==="map"?"active":""} onClick={()=>setTab("map")}>⌖ <span>Medidores</span></button></nav><div className="user-box"><b>{session.user.email}</b><small>{organization?.organizations.name}</small><button onClick={()=>supabase.auth.signOut()}>Cerrar sesión</button></div></aside>
  <section className="work"><header><div><p>MUNICIPALIDAD DE RINCÓN DE LOS SAUCES</p><h1>{tab==="dashboard"?"Inteligencia energética":tab==="invoices"?"Seguimiento de facturas":tab==="tariffs"?"Oportunidades de ahorro":"Mapa de medidores"}</h1></div><div className="head-actions"><button className="secondary" onClick={analyze} disabled={busy}>Analizar ahora</button><button onClick={()=>fileRef.current?.click()} disabled={busy}>{busy?"Procesando…":"＋ Cargar ZIP / CSV"}</button><input hidden ref={fileRef} type="file" accept=".zip,.csv" onChange={e=>upload(e.target.files?.[0])}/></div></header>

  {tab==="dashboard"&&<><div className="kpis"><article><span>Gasto histórico</span><strong>{money.format(total)}</strong><small>{invoices.length} facturas cargadas</small></article><article><span>Consumo registrado</span><strong>{number.format(kwh)} <i>kWh</i></strong><small>{meters.length} medidores activos</small></article><article className="green"><span>Ahorro anual potencial</span><strong>{money.format(annualSaving)}</strong><small>{opportunities.length} oportunidades</small></article><article className={missing.length?"warning-card":""}><span>Facturas faltantes</span><strong>{missing.length}</strong><small>{missing.length?"Requieren revisión":"Seguimiento al día"}</small></article></div><div className="analysis-grid"><section className="panel"><Title title="Últimas facturas" sub="Historial guardado en Supabase" action={()=>setTab("invoices")}/><InvoiceTable invoices={invoices.slice(0,8)}/></section><aside className="panel findings"><Title title="Alertas mensuales" sub="Medidores que no aparecieron en la carga"/>{missing.length?missing.slice(0,6).map(x=><div className="finding" key={x.id}><i>!</i><div><b>{x.meters?.tracking_code||"Sin ID"}</b><p>{x.message}</p></div></div>):<div className="empty">No hay facturas faltantes.</div>}</aside></div></>}
  {tab==="invoices"&&<section className="panel"><Title title="Facturas importadas" sub={`${periods.length} períodos · ${invoices.length} registros`}/><InvoiceTable invoices={invoices}/></section>}
  {tab==="tariffs"&&<div className="projection"><section className="panel"><Title title="Oportunidades detectadas" sub="Calculadas con la información histórica"/>{opportunities.length?opportunities.map(o=><div className="opportunity" key={o.id}><span className={`tag ${o.priority}`}>{o.priority}</span><div><b>{o.title}</b><small>{o.meters?.sites?.name||o.meters?.meter_number||"General"}</small></div><strong>{money.format(o.estimated_annual_saving)}<small>/año</small></strong></div>):<div className="empty">Ejecutá “Analizar ahora” después de cargar las facturas.</div>}</section><aside className="result"><p>RESULTADO PROYECTADO</p><strong>{money.format(annualSaving)}</strong><span>ahorro anual</span><div className="gauge"><i style={{width:`${Math.min(100,total?annualSaving/(total*6)*100:0)}%`}}/></div><div className="result-grid"><span>Ahorro a 5 años<b>{money.format(annualSaving*5)}</b></span><span>Oportunidades<b>{opportunities.length}</b></span></div></aside></div>}
  {tab==="map"&&<div className="map-layout"><section className="panel map-panel"><div className="map-head"><div><h2>Ubicación de suministros</h2><p>Medidores identificados por su ID permanente</p></div><span>{meters.length} medidores</span></div><div className="map"><div className="river"/><b className="zone west">OESTE</b><b className="zone center">CENTRO</b><b className="zone east">ESTE</b>{markerData.map(m=><div key={m.id} className={`marker ${selectedMeter===m.id?"selected":""}`} style={{left:`${m.x}%`,top:`${m.y}%`}} onClick={()=>setSelectedMeter(m.id)}><i>⚡</i><label>{m.sites?.name||"Sin ubicación"}<small>{m.tracking_code} · {m.meter_number}</small></label></div>)}</div></section><aside className="panel meter-list"><Title title="Medidores" sub="Seguimiento permanente"/>{meters.map(m=><button className={selectedMeter===m.id?"active":""} key={m.id} onClick={()=>setSelectedMeter(m.id)}><i>●</i><div><b>{m.tracking_code}</b><small>{m.sites?.name||"Sin ubicación"} · {m.meter_number}</small></div><em>{m.current_tariff_code||"Sin tarifa"}</em></button>)}</aside></div>}
  </section>{toast&&<div className="toast">{toast}</div>}</main>;
}

function Title({title,sub,action}:{title:string;sub:string;action?:()=>void}){return <div className="panel-title"><div><h2>{title}</h2><p>{sub}</p></div>{action&&<button onClick={action}>Ver todas →</button>}</div>}
function InvoiceTable({invoices}:{invoices:Invoice[]}){return <div className="table"><table><thead><tr><th>ID seguimiento</th><th>Establecimiento</th><th>Período</th><th>Consumo</th><th>Demanda</th><th>Tarifa</th><th>Importe</th></tr></thead><tbody>{invoices.map(i=>{const m=i.invoice_measurements?.[0];return <tr key={i.id}><td><b>{i.meters?.tracking_code||"—"}</b><small>{i.meters?.meter_number}</small></td><td><b>{i.meters?.sites?.name||"Sin ubicación"}</b></td><td>{i.period_start.slice(0,7)}</td><td><b>{number.format(Number(m?.active_energy_kwh||0))} kWh</b></td><td>{number.format(Number(m?.demand_kw||0))} kW</td><td><span className="tag low">{i.current_tariff_code||"S/D"}</span></td><td><strong className="save">{money.format(Number(i.total_amount||0))}</strong></td></tr>})}{!invoices.length&&<tr><td colSpan={7}><div className="empty">Todavía no se cargaron facturas.</div></td></tr>}</tbody></table></div>}
