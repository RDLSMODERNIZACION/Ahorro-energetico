"use client";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "./lib/supabase";
import { HistoricalAnalysis } from "./analysis-charts";
import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";
import { EpenOptimizationPanel, type EpenOptimizationMeter, type EpenOptimizationResponse } from "./epen-optimization-panel";
import { MetersMap } from "./meters-map";
import { PublicLightingPanel } from "./public-lighting-panel";

const API = "https://ahorro-energetico.onrender.com";
const money = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
const number = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
type Organization = { organization_id:string; role:string; organizations:{id:string;name:string} };
type Meter = { id:string;tracking_code:string;meter_number:string;nis?:string;supply_number?:string;contract_number?:string;service_code?:string;service_name?:string;cadastral_number?:string;customer_number?:string;customer_type?:string;contract_type?:string;current_tariff_code?:string;voltage_level?:string;contracted_kw_peak?:number;contracted_kw_off_peak?:number;status?:"active"|"inactive"|"removed";expected_monthly?:boolean;first_seen_period?:string;last_seen_period?:string;notes?:string;sites?:{name:string;address?:string} };
type Measurement = {active_energy_kwh?:number;reactive_energy_kvarh?:number;demand_kw?:number;power_factor?:number;resolved_power_factor?:number;power_factor_source?:string;power_factor_penalized?:boolean;tangent_phi?:number;reactive_surcharge_percent?:number;registered_demand_peak_kw?:number;registered_demand_off_peak_kw?:number;meter_number?:string;measurement_type?:string};
type InvoiceLine = {concept_code?:string;description?:string;quantity?:number;unit_price?:number;net_amount?:number};
type Invoice = {id:string;meter_id:string;invoice_number?:string;billing_period?:string;period_start:string;period_end:string;issue_date?:string;due_date?:string;total_amount:number;amount_due?:number;current_tariff_code?:string;tariff_name?:string;tariff_class?:string;voltage_level?:string;contracted_kw_peak?:number;contracted_kw_off_peak?:number;vat_amount?:number;previous_debt_amount?:number;meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:InvoiceLine[]};
type Missing = {id:string;expected_period:string;message:string;status:string;meters?:{tracking_code:string;meter_number:string;sites?:{name:string}}};
type Opportunity = {id:string;title:string;priority:string;estimated_annual_saving:number;estimated_investment:number;status:string;meters?:{meter_number:string;sites?:{name:string}}};
type TariffAssessment = {meter_id:string;meter:Meter;current_tariff?:string;recommended_tariff:string;status:"correct"|"power_review"|"change_candidate"|"provisional";reasons:string[];periods_analyzed:number;billing_period?:string;consumption_kwh:number;maximum_demand_kw:number;contracted_kw:number;recommended_kw:number;power_factor?:number;power_excess_kw?:number;power_unit_price?:number;power_saving_source?:"invoice_excess"|"contracted_reduction";power_monthly_saving:number;power_annual_saving:number;reactive_monthly_saving:number;reactive_annual_saving:number;tariff_current_simulated?:number;tariff_recommended_simulated?:number;tariff_monthly_saving:number;tariff_annual_saving:number;tariff_simulation_available:boolean;tariff_price_source?:"official"|"observed";official_schedule?:{resolution_number:string;consumption_month:string;billing_month:string;valid_from:string;valid_to:string};estimated_monthly_saving:number;estimated_annual_saving:number;confidence:number;requires_epen_review:boolean};
type TariffSaving = {meter_id:string;meter_number:string;supply_number?:string;service_name?:string;billing_period:string;current_tariff:string;recommended_tariff:string;used_kw:number;consumption_kwh:number;current_cost_with_vat:number;recommended_cost_with_vat:number;monthly_saving_with_vat:number;annual_saving_with_vat:number};
type AdvancedTariffSummaryMeter={
  meter_id:string;
  billing_period:string;
  current_tariff:string;
  recommended_tariff:string;
  monthly_saving:number;
  annualized_saving:number;
  available:boolean;
  resolution_number?:string|null;
};
type AdvancedTariffSummary={
  billing_period:string;
  monthly_saving:number;
  annualized_saving:number;
  candidate_count:number;
  valued_count:number;
  meters:AdvancedTariffSummaryMeter[];
};
type TariffSavingResponse = {candidates:TariffSaving[];candidate_count:number;positive_candidate_count:number;monthly_saving_with_vat:number;annual_saving_with_vat:number;vat_percent:number};

async function api<T>(path:string, session:Session, init?:RequestInit):Promise<T>{
  const retryable=!init?.method||init.method.toUpperCase()==="GET";
  let lastError:Error|undefined;
  for(let attempt=0;attempt<(retryable?3:1);attempt++){
    try{
      const response=await fetch(`${API}${path}`,{...init,cache:"no-store",headers:{Authorization:`Bearer ${session.access_token}`,...(init?.body instanceof FormData?{}:{"Content-Type":"application/json"}),...(init?.headers||{})}});
      if(response.ok){if(response.status===204)return undefined as T;return response.json()}
      const body=await response.text();
      const error=new Error(body||`Error ${response.status}`);
      if(!retryable||![500,502,503,504].includes(response.status))throw error;
      lastError=error;
    }catch(error){lastError=error instanceof Error?error:new Error("Error de conexión");if(!retryable)throw lastError}
    if(attempt<2)await new Promise(resolve=>setTimeout(resolve,350*(attempt+1)));
  }
  throw lastError||new Error("No se pudo consultar la API");
}


function dashboardPowerDemand(i:Invoice){
  return Math.max(0,...(i.invoice_measurements||[]).map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));
}
function dashboardPowerContract(i:Invoice){
  const line=Math.max(0,...(i.invoice_lines||[]).filter(x=>["DEP","DEM"].includes(String(x.concept_code||"").toUpperCase())).map(x=>Number(x.quantity||0)));
  return Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||line||0);
}
function dashboardPowerRate(i:Invoice){
  return Math.max(0,...(i.invoice_lines||[]).filter(x=>["DEP","DEM"].includes(String(x.concept_code||"").toUpperCase())).map(x=>Number(x.unit_price||0)));
}
function buildDashboardPowerCurve(invoices:Invoice[],period:string){
  const monthNumber=Number(String(period||"").slice(5,7));
  const meterIds=[...new Set(invoices.map(i=>i.meter_id))];
  const meters=meterIds.map(meterId=>{
    const history=invoices.filter(i=>i.meter_id===meterId&&dashboardPowerDemand(i)>0).sort((a,b)=>String(a.billing_period||a.period_start).localeCompare(String(b.billing_period||b.period_start)));
    const latestContract=[...history].reverse().find(i=>dashboardPowerContract(i)>0);
    const latestRate=[...history].reverse().find(i=>dashboardPowerRate(i)>0);
    const currentKw=latestContract?dashboardPowerContract(latestContract):0;
    const tariffCode=latestContract?.current_tariff_code||latestContract?.meters?.current_tariff_code;
    const minimumKw=minimumContractedKw(tariffCode);
    const rate=latestRate?dashboardPowerRate(latestRate):0;
    const rows=Array.from({length:12},(_,idx)=>{
      const target=idx+1;
      const demands=history.filter(i=>Number(String(i.billing_period||i.period_start).slice(5,7))===target).map(dashboardPowerDemand);
      const proposalKw=demands.length?Math.max(minimumKw,...demands):0;
      const reducibleKw=proposalKw>0?Math.max(0,currentKw-proposalKw):0;
      return{monthNumber:target,proposalKw,saving:reducibleKw*rate*1.30};
    });
    const selected=rows.find(r=>r.monthNumber===monthNumber);
    return{meterId,currentKw,rate,rows,monthlySaving:Number(selected?.saving||0),annualSaving:rows.reduce((s,r)=>s+r.saving,0)};
  }).filter(x=>x.currentKw>0&&x.rate>0);
  return{
    meters,
    monthlySaving:meters.reduce((s,x)=>s+x.monthlySaving,0),
    annualSaving:meters.reduce((s,x)=>s+x.annualSaving,0),
    opportunityMeterIds:new Set(meters.filter(x=>x.monthlySaving>0).map(x=>x.meterId))
  };
}

function renderAiRichText(text:string,onOpenReference?:(reference:string)=>void){
  const normalized=text
    .replace(/\r/g,"")
    .replace(/\s+(?=\d+\.\s+\*\*)/g,"\n")
    .replace(/\s+(?=•\s+)/g,"\n")
    .replace(/\s+(?=-\s+\*\*)/g,"\n")
    .trim();

  const openRef=(value:string)=>{
    const cleaned=value
      .replace(/\*\*/g,"")
      .replace(/^(medidor|suministro|id)\s*[:#-]?\s*/i,"")
      .trim();
    if(cleaned)onOpenReference?.(cleaned);
  };

  const isReference=(value:string)=>{
    const v=value.replace(/\*\*/g,"").trim();
    return /(?:medidor|suministro|id)\s*[:#-]?\s*[A-Za-z0-9-]{3,}/i.test(v)
      || /^[0-9]{5,12}$/.test(v);
  };

  const renderInline=(line:string,keyPrefix:string)=>{
    const parts=line.split(/(\*\*[^*]+\*\*)/g).filter(Boolean);
    return parts.map((part,index)=>{
      if(part.startsWith("**")&&part.endsWith("**")){
        const label=part.slice(2,-2);
        if(onOpenReference&&isReference(label)){
          return <button type="button" className="ai-inline-link" key={`${keyPrefix}-b-${index}`} onClick={()=>openRef(label)}>{label}</button>;
        }
        return <strong key={`${keyPrefix}-b-${index}`}>{label}</strong>;
      }
      return <span key={`${keyPrefix}-t-${index}`}>{part}</span>;
    });
  };

  const clickFromLine=(line:string)=>{
    if(!onOpenReference)return;
    const meter=line.match(/medidor\s*[:#-]?\s*([A-Za-z0-9-]{3,})/i);
    if(meter){openRef(meter[1]);return}
    const supply=line.match(/suministro\s*[:#-]?\s*([A-Za-z0-9-]{3,})/i);
    if(supply){openRef(supply[1]);}
  };

  return normalized.split("\n").filter(Boolean).map((raw,index)=>{
    const line=raw.trim();
    const numbered=line.match(/^(\d+)\.\s+(.*)$/);
    const bullet=line.match(/^(?:•|-)\s+(.*)$/);
    const clickable=Boolean(onOpenReference)&&/(medidor|suministro)\s*[:#-]?\s*[A-Za-z0-9-]{3,}/i.test(line);

    if(numbered){
      return <div className={`ai-rich-item${clickable?" clickable":""}`} key={`n-${index}`} onClick={()=>clickable&&clickFromLine(numbered[2])}>
        <span className="ai-rich-number">{numbered[1]}</span>
        <div>{renderInline(numbered[2],`n-${index}`)}</div>
        {clickable&&<em className="ai-open-hint">Abrir análisis →</em>}
      </div>;
    }
    if(bullet){
      return <div className={`ai-rich-item${clickable?" clickable":""}`} key={`u-${index}`} onClick={()=>clickable&&clickFromLine(bullet[1])}>
        <span className="ai-rich-bullet">•</span>
        <div>{renderInline(bullet[1],`u-${index}`)}</div>
        {clickable&&<em className="ai-open-hint">Abrir análisis →</em>}
      </div>;
    }
    if(line.startsWith("## ")){
      return <h4 className="ai-rich-heading" key={`h-${index}`}>{line.slice(3)}</h4>;
    }
    return <p className={`ai-rich-paragraph${clickable?" clickable":""}`} key={`p-${index}`} onClick={()=>clickable&&clickFromLine(line)}>{renderInline(line,`p-${index}`)}{clickable&&<em className="ai-open-hint">Abrir análisis →</em>}</p>;
  });
}
export default function Home(){
  const[session,setSession]=useState<Session|null>(null),[authReady,setAuthReady]=useState(false);
  const[epenOptimization,setEpenOptimization]=useState<EpenOptimizationMeter[]>([]);
  const[advancedTariffSummary,setAdvancedTariffSummary]=useState<AdvancedTariffSummary|null>(null);
  const[email,setEmail]=useState(""),[password,setPassword]=useState(""),[loginError,setLoginError]=useState(""),[loginBusy,setLoginBusy]=useState(false);
  const[organization,setOrganization]=useState<Organization|null>(null),[meters,setMeters]=useState<Meter[]>([]),[invoices,setInvoices]=useState<Invoice[]>([]),[missing,setMissing]=useState<Missing[]>([]),[opportunities,setOpportunities]=useState<Opportunity[]>([]),[assessments,setAssessments]=useState<TariffAssessment[]>([]),[tariffSavings,setTariffSavings]=useState<TariffSaving[]>([]);
  const[tab,setTab]=useState<"dashboard"|"invoices"|"framing"|"tariffs"|"map"|"ai">("dashboard"),[busy,setBusy]=useState(false),[toast,setToast]=useState(""),[selectedMeter,setSelectedMeter]=useState(""),[selectedInvoice,setSelectedInvoice]=useState<Invoice|null>(null),[yearFilter,setYearFilter]=useState("all"),[monthFilter,setMonthFilter]=useState("all"),[search,setSearch]=useState(""),[framingFilter,setFramingFilter]=useState("all"),[mapSearch,setMapSearch]=useState("");
  const[aiQuery,setAiQuery]=useState(""),[aiAnswer,setAiAnswer]=useState("Seleccioná una consulta sugerida o escribí qué querés analizar."),[aiBusy,setAiBusy]=useState(false);
  const[invoiceSubTab,setInvoiceSubTab]=useState<"received"|"missing"|"publicLighting">("received");
  const fileRef=useRef<HTMLInputElement>(null);
  const invoiceFiltersInitialized=useRef(false);
  const loadedDataKey=useRef("");
  useEffect(()=>{
    function hideLegacyMissingPanelV31(){
      const marker="Estos medidores no aparecen en el archivo del período seleccionado";
      const nodes=[...document.querySelectorAll("section,div")];
      const candidates=nodes.filter(el=>{
        const text=(el.textContent||"").trim();
        return text.includes(marker)&&text.includes("Faltan")&&text.includes("facturas");
      });

      // Elegimos el contenedor mas chico que contiene todo el cuadro viejo.
      const target=candidates.sort((a,b)=>(a.textContent?.length||0)-(b.textContent?.length||0))[0] as HTMLElement|undefined;
      if(!target)return;

      let panel:HTMLElement=target;
      while(panel.parentElement){
        const parent=panel.parentElement;
        const parentText=(parent.textContent||"");
        if(!parentText.includes(marker))break;
        if(parent.classList.contains("panel")||parent.tagName==="SECTION"){
          panel=parent;
          break;
        }
        panel=parent;
      }

      panel.style.display="none";
      panel.setAttribute("data-hidden-legacy-missing","true");
    }

    const timer=window.setTimeout(hideLegacyMissingPanelV31,50);
    const observer=new MutationObserver(()=>hideLegacyMissingPanelV31());
    observer.observe(document.body,{childList:true,subtree:true});
    return()=>{
      window.clearTimeout(timer);
      observer.disconnect();
    };
  },[]);
useEffect(()=>{supabase.auth.getSession().then(({data})=>{setSession(data.session);setAuthReady(true)});const{data}=supabase.auth.onAuthStateChange((_e,s)=>setSession(s));return()=>data.subscription.unsubscribe()},[]);
  const orgId=organization?.organization_id;
  const load=useCallback(async(s:Session,org?:string)=>{
    try{
      let target=org;
      if(!target){const orgs=await api<Organization[]>("/api/organizations",s);if(!orgs.length)throw new Error("Tu usuario todavía no está asociado a la Municipalidad");setOrganization(orgs[0]);target=orgs[0].organization_id}
      loadedDataKey.current=`${s.user.id}:${target}`;
      const [m,i,o]=await Promise.all([api<Meter[]>(`/api/organizations/${target}/meters`,s),api<Invoice[]>(`/api/organizations/${target}/invoices?limit=5000`,s),api<Opportunity[]>(`/api/organizations/${target}/opportunities`,s).catch(()=>[])]);
      setMeters(m);setInvoices(i);setOpportunities(o);setSelectedMeter(current=>current||m[0]?.id||"");if(!invoiceFiltersInitialized.current&&i.length){const latest=[...new Set(i.map(x=>(x.billing_period||x.period_start).slice(0,7)))].sort().reverse()[0];if(latest){setYearFilter(latest.slice(0,4));setMonthFilter(latest.slice(5,7));invoiceFiltersInitialized.current=true}}
      const [miss,frames,tariffResult]=await Promise.all([api<Missing[]>(`/api/organizations/${target}/missing-invoices`,s).catch(()=>[]),api<TariffAssessment[]>(`/api/organizations/${target}/tariff-assessments?v=14`,s).catch(()=>[]),api<TariffSavingResponse>(`/api/organizations/${target}/tariff-savings?v=1`,s).catch(e=>{setToast(`No se pudo cargar el ahorro tarifario: ${e instanceof Error?e.message:"Error desconocido"}`);return null})]);setMissing(miss);setAssessments(frames);setTariffSavings(tariffResult?.candidates||[]);const epen=await api<EpenOptimizationResponse>(`/api/organizations/${target}/epen-optimization?v=2`,s).catch(()=>null);setEpenOptimization(epen?.meters||[]);
    }catch(e){setToast(e instanceof Error?e.message:"No se pudieron cargar los datos")}
  },[]);
  useEffect(()=>{if(!session)return;const key=orgId?`${session.user.id}:${orgId}`:"";if(key&&loadedDataKey.current===key)return;load(session,orgId)},[session,orgId,load]);

  async function login(e:FormEvent){e.preventDefault();setLoginBusy(true);setLoginError("");const{error}=await supabase.auth.signInWithPassword({email,password});if(error)setLoginError(error.message);setLoginBusy(false)}
  async function upload(file?:File){if(!file||!session||!orgId)return;setBusy(true);try{const form=new FormData();form.append("organization_id",orgId);form.append("file",file);const result=await api<{imported:number;missing_count:number;duplicate:boolean}>("/api/imports/invoices",session,{method:"POST",body:form});setToast(result.duplicate?"Este archivo ya había sido cargado":`${result.imported} facturas importadas · ${result.missing_count} faltantes`);await load(session,orgId)}catch(e){setToast(e instanceof Error?e.message:"No se pudo importar") }finally{setBusy(false);setTimeout(()=>setToast(""),5000)}}
  async function analyze(){if(!session||!orgId)return;setBusy(true);try{const r=await api<{opportunities_created:number}>(`/api/organizations/${orgId}/analysis/run`,session,{method:"POST"});setToast(`${r.opportunities_created} oportunidades detectadas`);await load(session,orgId)}catch(e){setToast(e instanceof Error?e.message:"No se pudo analizar")}finally{setBusy(false)}}
  async function runAiQuery(text?:string){
    const question=(text??aiQuery).trim();
    if(!question){setAiAnswer("Escribí una consulta.");return}
    if(!session||!orgId){setAiAnswer("No hay sesión u organización activa.");return}
    setAiBusy(true);
    try{
      const result=await api<{answer:string;model?:string;latest_period?:string}>(
        "/api/ai/query",
        session,
        {method:"POST",body:JSON.stringify({organization_id:orgId,question})}
      );
      setAiAnswer(result.answer);
    }catch(error){
      setAiAnswer(error instanceof Error?error.message:"No se pudo consultar la IA");
    }finally{
      setAiBusy(false);
    }
  }
function openAiReference(reference:string){
  const ref=reference.trim().toLowerCase().replace(/\s+/g,"");
  const normalize=(v?:string)=>String(v||"").toLowerCase().replace(/\s+/g,"").replace(/^0+/,"");

  const meter=meters.find(m=>
    normalize(m.meter_number)===normalize(ref) ||
    normalize(m.supply_number)===normalize(ref) ||
    normalize(m.tracking_code)===normalize(ref) ||
    normalize(m.id)===normalize(ref)
  );

  if(!meter){
    setToast(`No encontré el medidor/suministro ${reference}`);
    setTimeout(()=>setToast(""),3500);
    return;
  }

  const latest=[...invoices]
    .filter(i=>i.meter_id===meter.id)
    .sort((a,b)=>invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];

  if(latest){
    setTab("invoices");
    setInvoiceSubTab("received");
    setSelectedMeter(meter.id);
    setSelectedInvoice(latest);
    const p=invoiceMonth(latest);
    if(p){
      setYearFilter(p.slice(0,4));
      setMonthFilter(p.slice(5,7));
    }
  }else{
    setToast(`El medidor ${meter.meter_number||reference} no tiene factura para abrir`);
    setTimeout(()=>setToast(""),3500);
  }
}
async function updateMeterStatus(meterId:string,status:"active"|"inactive"|"removed"){if(!session||!orgId)return;setBusy(true);try{await api(`/api/meters/${meterId}/billing-status`,session,{method:"PUT",body:JSON.stringify({status})});setToast(status==="active"?"El medidor vuelve al seguimiento mensual":status==="removed"?"Baja confirmada: ya no se esperarán facturas":"Medidor marcado como posible baja");await load(session,orgId)}catch(e){setToast(e instanceof Error?e.message:"No se pudo actualizar el medidor")}finally{setBusy(false);setTimeout(()=>setToast(""),4000)}}

  const total=invoices.reduce((s,x)=>s+Number(x.total_amount||0),0),kwh=invoices.reduce((s,x)=>s+(x.invoice_measurements||[]).reduce((a,m)=>a+Number(m.active_energy_kwh||0),0),0),annualSaving=assessments.length?assessments.reduce((s,x)=>s+Number(x.estimated_annual_saving||0),0):opportunities.filter(x=>x.status!=="dismissed").reduce((s,x)=>s+Number(x.estimated_annual_saving||0),0);
  const invoiceMonth=(x:Invoice)=>(x.billing_period||x.period_start).slice(0,7);
  const periods=[...new Set(invoices.map(invoiceMonth))].sort().reverse();
  const years=[...new Set(periods.map(x=>x.slice(0,4)))];
  const filteredInvoices=invoices.filter(i=>{const p=invoiceMonth(i),m=i.meters,q=search.trim().toLowerCase();return(yearFilter==="all"||p.startsWith(yearFilter))&&(monthFilter==="all"||p.slice(5,7)===monthFilter)&&(!q||[m?.service_name,m?.sites?.name,m?.meter_number,m?.tracking_code,m?.supply_number,i.invoice_number].some(v=>v?.toLowerCase().includes(q)))});
  const controlPeriod=yearFilter!=="all"&&monthFilter!=="all"?`${yearFilter}-${monthFilter}`:periods[0]||"";
  // Solo una baja confirmada deja de exigir factura mensual.
  const activeMeters=meters.filter(m=>(m.status||"active")!=="removed");
  const lifecycleMeters=meters.filter(m=>m.status==="inactive"||m.status==="removed");
  const presentMeterIds=new Set(invoices.filter(i=>invoiceMonth(i)===controlPeriod).map(i=>i.meter_id));
  const missingPeriodMeters=activeMeters.filter(m=>!presentMeterIds.has(m.id));
  const visibleMissingPeriodMeters=missingPeriodMeters.filter(m=>{const q=search.trim().toLowerCase();return!q||[m.service_name,m.sites?.name,m.meter_number,m.tracking_code,m.supply_number].some(v=>v?.toLowerCase().includes(q))});
  const visibleAssessments=assessments.filter(x=>framingFilter==="all"||x.status===framingFilter);
  const latestInvoiceByMeter=[...invoices].sort((a,b)=>invoiceMonth(b).localeCompare(invoiceMonth(a))).filter((invoice,index,list)=>list.findIndex(x=>x.meter_id===invoice.meter_id)===index);
  const localPowerAnnual=latestInvoiceByMeter.reduce((sum,invoice)=>sum+invoicePowerSaving(invoice).amount*12,0);
  const localReactiveAnnual=latestInvoiceByMeter.reduce((sum,invoice)=>sum+invoiceReactiveSaving(invoice)*12,0);
  const powerAnnual=assessments.length?assessments.reduce((s,x)=>s+Number(x.power_annual_saving||0),0):localPowerAnnual;
  const reactiveAnnual=assessments.length?assessments.reduce((s,x)=>s+Number(x.reactive_annual_saving||0),0):localReactiveAnnual;
  const rateAnnual=tariffSavings.length?tariffSavings.reduce((s,x)=>s+Number(x.annual_saving_with_vat||0),0):assessments.reduce((s,x)=>s+Number(x.tariff_annual_saving||0),0),tariffAnnual=powerAnnual+reactiveAnnual+rateAnnual;
  const reviewCount=assessments.length?assessments.filter(x=>x.status!=="correct").length:latestInvoiceByMeter.filter(i=>invoicePowerSaving(i).amount>0||invoiceReactiveSaving(i)>0).length;
  const powerSavingCount=assessments.length?assessments.filter(x=>x.power_monthly_saving>0).length:latestInvoiceByMeter.filter(i=>invoicePowerSaving(i).amount>0).length;
  const reactiveSavingCount=assessments.length?assessments.filter(x=>x.reactive_monthly_saving>0).length:latestInvoiceByMeter.filter(i=>invoiceReactiveSaving(i)>0).length;
    const aiAlertData=useMemo(()=>{
    const latest=periods[0]||"";
    const previous=periods[1]||"";
    const last6=periods.slice(0,6);
    const latestRows=invoices.filter(i=>invoiceMonth(i)===latest);
    const previousRows=invoices.filter(i=>invoiceMonth(i)===previous);
    const byMeter6=new Map<string,Invoice[]>();
    for(const i of invoices){
      if(!last6.includes(invoiceMonth(i)))continue;
      const arr=byMeter6.get(i.meter_id)||[];
      arr.push(i);byMeter6.set(i.meter_id,arr);
    }

    const critical:any[]=[];
    const opportunities:any[]=[];
    const changes:any[]=[];

    for(const i of latestRows){
      const x=metrics(i),m=i.meters;
      const history=byMeter6.get(i.meter_id)||[];
      const past=history.filter(h=>invoiceMonth(h)!==latest);
      const avgKwh=past.length?past.reduce((s,h)=>s+metrics(h).kwh,0)/past.length:0;
      const avgAmount=past.length?past.reduce((s,h)=>s+Number(h.total_amount||0),0)/past.length:0;
      const prev=previousRows.find(p=>p.meter_id===i.meter_id);
      const prevM=prev?metrics(prev):null;
      const currentAmount=Number(i.total_amount||0);

      if(x.pf>0&&x.pf<.95){
        critical.push({kind:"pf",score:(.95-x.pf)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`Cos φ ${x.pf.toFixed(3)} · revisar compensación reactiva`,invoice:i,meterId:i.meter_id});
      }
      if(avgKwh>0&&x.kwh>avgKwh*1.3){
        critical.push({kind:"consumption",score:(x.kwh/avgKwh-1)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`Consumo +${((x.kwh/avgKwh-1)*100).toFixed(0)}% vs promedio 6 meses`,invoice:i,meterId:i.meter_id});
      }
      if(avgAmount>0&&currentAmount>avgAmount*1.35){
        critical.push({kind:"amount",score:(currentAmount/avgAmount-1)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`Importe +${((currentAmount/avgAmount-1)*100).toFixed(0)}% vs promedio`,invoice:i,meterId:i.meter_id});
      }

      if(x.excess>0){
        const monthly=invoicePowerSaving(i).amount;
        opportunities.push({kind:"power",value:monthly,label:m?.service_name||m?.meter_number||"Medidor",detail:`${number.format(x.excess)} kW sobrantes · ${money.format(monthly)}/mes`,invoice:i,meterId:i.meter_id});
      }
      const reactive=invoiceReactiveSaving(i);
      if(reactive>0){
        opportunities.push({kind:"reactive",value:reactive,label:m?.service_name||m?.meter_number||"Medidor",detail:`Penalización reactiva evitable · ${money.format(reactive)}/mes`,invoice:i,meterId:i.meter_id});
      }
      const tariff=tariffSavings.find(t=>t.meter_id===i.meter_id&&String(t.billing_period).slice(0,7)===latest);
      if(Number(tariff?.monthly_saving_with_vat||0)>0){
        opportunities.push({kind:"tariff",value:Number(tariff?.monthly_saving_with_vat||0),label:m?.service_name||m?.meter_number||"Medidor",detail:`Cambio tarifario · ${money.format(Number(tariff?.monthly_saving_with_vat||0))}/mes`,invoice:i,meterId:i.meter_id});
      }

      if(prev&&prevM){
        const consumptionDelta=prevM.kwh?((x.kwh-prevM.kwh)/prevM.kwh)*100:0;
        const demandDelta=prevM.demand?((x.demand-prevM.demand)/prevM.demand)*100:0;
        const amountDelta=Number(prev.total_amount||0)?((currentAmount-Number(prev.total_amount||0))/Number(prev.total_amount||0))*100:0;
        if(Math.abs(consumptionDelta)>=20||Math.abs(demandDelta)>=20||Math.abs(amountDelta)>=20){
          const bits=[
            Math.abs(consumptionDelta)>=20?`consumo ${consumptionDelta>=0?"+":""}${consumptionDelta.toFixed(0)}%`:"",
            Math.abs(demandDelta)>=20?`demanda ${demandDelta>=0?"+":""}${demandDelta.toFixed(0)}%`:"",
            Math.abs(amountDelta)>=20?`importe ${amountDelta>=0?"+":""}${amountDelta.toFixed(0)}%`:""
          ].filter(Boolean);
          changes.push({label:m?.service_name||m?.meter_number||"Medidor",detail:bits.join(" · "),positive:consumptionDelta<0&&amountDelta<0,invoice:i,meterId:i.meter_id});
        }
      }
    }

    for(const m of missingPeriodMeters){
      critical.push({kind:"missing",score:60,label:m.service_name||m.meter_number||"Medidor",detail:`Factura faltante en ${controlPeriod||latest}`,invoice:null,meterId:m.id});
    }

    critical.sort((a,b)=>b.score-a.score);
    opportunities.sort((a,b)=>b.value-a.value);

    return{
      latest,
      critical:critical.slice(0,8),
      opportunities:opportunities.slice(0,8),
      changes:changes.slice(0,8),
      criticalCount:critical.length,
      opportunityCount:opportunities.length
    };
  },[invoices,periods,missingPeriodMeters,controlPeriod,tariffSavings]);
  const dashboardPeriod=periods[0]||"";
  const dashboardPeriodLabel=dashboardPeriod?new Date(Number(dashboardPeriod.slice(0,4)),Number(dashboardPeriod.slice(5,7))-1,1).toLocaleString("es-AR",{month:"long",year:"numeric"}):"Sin período";
  useEffect(()=>{
    let cancelled=false;
    async function loadAdvancedTariffSummary(){
      if(!session||!orgId||!dashboardPeriod)return;
      try{
        const result=await api<AdvancedTariffSummary>(`/api/organizations/${orgId}/tariff-saving-summary?period=${dashboardPeriod}`,session);
        if(!cancelled)setAdvancedTariffSummary(result);
      }catch{
        if(!cancelled)setAdvancedTariffSummary(null);
      }
    }
    loadAdvancedTariffSummary();
    return()=>{cancelled=true};
  },[session,orgId,dashboardPeriod]);
  const dashboardInvoices=invoices.filter(i=>invoiceMonth(i)===dashboardPeriod);
  const dashboardPresentIds=new Set(dashboardInvoices.map(i=>i.meter_id));
  const dashboardReceived=[...dashboardPresentIds].filter(id=>activeMeters.some(m=>m.id===id)).length;
  const dashboardMissing=activeMeters.filter(m=>!dashboardPresentIds.has(m.id));
  const dashboardPowerCurve=buildDashboardPowerCurve(invoices,dashboardPeriod);
  const dashboardPowerMonthly=dashboardPowerCurve.monthlySaving;
  const dashboardPowerAnnual=dashboardPowerCurve.annualSaving;
  const dashboardReactiveMonthly=dashboardInvoices.reduce((sum,i)=>sum+invoiceReactiveSaving(i),0);
  const legacyDashboardRateMonthly=tariffSavings.filter(x=>String(x.billing_period).slice(0,7)===dashboardPeriod).reduce((sum,x)=>sum+Number(x.monthly_saving_with_vat||0),0);

  const dashboardAdvancedRows=advancedTariffSummary?.billing_period===dashboardPeriod
    ?advancedTariffSummary.meters.filter(x=>x.available&&Number(x.monthly_saving||0)>0)
    :[];

  const dashboardAdvancedMeterIds=new Set(dashboardAdvancedRows.map(x=>x.meter_id));

  const dashboardOptimizationFallbackRows=dashboardInvoices.map(i=>{
    if(dashboardAdvancedMeterIds.has(i.meter_id))return null;

    const opt=epenOptimization.find(x=>x.meter_id===i.meter_id);
    if(!opt)return null;

    const mtSaving=["strong","candidate","preliminary"].includes(opt.mt.status)
      ?Number(opt.mt.monthly_saving_before_taxes||0)
      :0;

    const t4Saving=opt.t4.status==="candidate"
      ?Number(opt.t4.monthly_saving_before_taxes||0)
      :0;

    const saving=mtSaving>0?mtSaving:t4Saving;
    if(saving<=0)return null;

    return{
      meter_id:i.meter_id,
      monthly_saving:saving,
      scenario:mtSaving>0?"mt":"t4"
    };
  }).filter((x):x is {meter_id:string;monthly_saving:number;scenario:"mt"|"t4"}=>Boolean(x));

  const dashboardOptimizationFallbackMonthly=dashboardOptimizationFallbackRows.reduce((sum,x)=>sum+x.monthly_saving,0);

  const dashboardRateMonthly=advancedTariffSummary?.billing_period===dashboardPeriod
    ?Number(advancedTariffSummary.monthly_saving||0)+dashboardOptimizationFallbackMonthly
    :legacyDashboardRateMonthly+dashboardOptimizationFallbackMonthly;

  const dashboardTariffValuedCount=
    dashboardAdvancedRows.length+
    dashboardOptimizationFallbackRows.length;
  const dashboardTotalMonthly=dashboardPowerMonthly+dashboardReactiveMonthly+dashboardRateMonthly;
  const dashboardTotalAnnual=dashboardPowerAnnual+(dashboardReactiveMonthly*12)+(dashboardRateMonthly*12);
  const dashboardOpportunityIds=new Set<string>();
  for(const i of dashboardInvoices){
    const hasPower=dashboardPowerCurve.opportunityMeterIds.has(i.meter_id);
    const hasReactive=invoiceReactiveSaving(i)>0;
    const hasTariff=dashboardAdvancedMeterIds.has(i.meter_id)||dashboardOptimizationFallbackRows.some(x=>x.meter_id===i.meter_id)||(advancedTariffSummary?.billing_period!==dashboardPeriod&&tariffSavings.some(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===dashboardPeriod&&Number(x.monthly_saving_with_vat||0)>0));
    if(hasPower||hasReactive||hasTariff)dashboardOpportunityIds.add(i.meter_id);
  }
  const dashboardLowPf=dashboardInvoices.filter(i=>{const p=metrics(i).pf;return p>0&&p<.95}).length;
  const dashboardPowerExcess=dashboardPowerCurve.opportunityMeterIds.size;
const openMeter=(i:Invoice)=>{setSelectedInvoice(i);setSelectedMeter(i.meter_id);setTab("invoices")};
  const openMeterById=(meterId?:string)=>{if(!meterId)return;const i=[...invoices].filter(x=>x.meter_id===meterId).sort((a,b)=>invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];if(i)openMeter(i)};
  const markerData=useMemo(()=>{const counters={west:0,center:0,east:0};return meters.map(m=>{const text=`${m.service_name||""} ${m.sites?.name||""} ${m.sites?.address||""}`.toLowerCase();const zone=text.includes("oeste")?"west":text.includes("este")?"east":text.match(/centro|municipalidad|san martin|belgrano|plaza|radio|biblioteca|deportiva|social/)?"center":text.match(/costa|pozo|bomba|agua|cloac|planta|vivero/)?(hashText(text)%2?"west":"east"):["west","center","east"][hashText(text)%3] as "west"|"center"|"east";const index=counters[zone]++,bounds=zone==="west"?[9,34]:zone==="center"?[37,62]:[65,91],width=bounds[1]-bounds[0],col=index%5,row=Math.floor(index/5);return{...m,zone,x:bounds[0]+4+col*(width-8)/4+(hashText(m.id)%3-1)*.8,y:14+(row*11)%70+(hashText(m.meter_number)%3-1)*.7}})},[meters]);
  const visibleMarkers=markerData.filter(m=>{const q=mapSearch.trim().toLowerCase();return!q||[m.service_name,m.sites?.name,m.sites?.address,m.meter_number,m.tracking_code,m.supply_number].some(v=>v?.toLowerCase().includes(q))});

  if(!authReady)return <main className="loading-page">Cargando…</main>;
  if(!session)return <main className="login-page"><section className="login-card"><div className="login-brand"><span>M</span><div><b>GESTIÓN</b><small>ENERGÉTICA MUNICIPAL</small></div></div><h1>Ingresar al sistema</h1><p>Facturación EPEN y oportunidades de ahorro</p><form onSubmit={login}><label>Correo electrónico<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required/></label>{loginError&&<div className="login-error">{loginError}</div>}<button disabled={loginBusy}>{loginBusy?"Ingresando…":"Ingresar"}</button></form><small>El usuario debe estar creado en Supabase Authentication.</small></section></main>;

  return <main className="shell"><aside className="side"><div className="brand"><span>M</span><div><b>GESTIÓN</b><small>ENERGÉTICA MUNICIPAL</small></div></div><nav><button className={tab==="dashboard"?"active":""} onClick={()=>setTab("dashboard")}>⌁ <span>Resumen</span></button><button className={tab==="invoices"?"active":""} onClick={()=>setTab("invoices")}>▤ <span>Facturas</span></button>
<button className={tab==="ai"?"active":""} onClick={()=>setTab("ai")}><i>✦</i><span>IA</span></button><button className={tab==="map"?"active":""} onClick={()=>setTab("map")}>⌖ <span>Medidores</span></button></nav><div className="user-box"><b>{session.user.email}</b><small>{organization?.organizations.name}</small><button onClick={()=>supabase.auth.signOut()}>Cerrar sesión</button></div></aside>
  <section className="work"><header><div><p>MUNICIPALIDAD DE RINCÓN DE LOS SAUCES</p><h1>{tab==="dashboard"?"Inteligencia energética":tab==="invoices"?"Seguimiento de facturas":tab==="framing"?"Encuadramiento tarifario":tab==="tariffs"?"Oportunidades de ahorro":"Mapa de medidores"}</h1></div><div className="head-actions"><button className="secondary" onClick={analyze} disabled={busy}>Analizar ahora</button><button onClick={()=>fileRef.current?.click()} disabled={busy}>{busy?"Procesando…":"＋ Cargar ZIP / CSV"}</button><input hidden ref={fileRef} type="file" accept=".zip,.csv" onChange={e=>upload(e.target.files?.[0])}/></div></header>

  {tab==="dashboard"&&<>
  <section className="panel dashboard-ai-ask">
    <div className="dashboard-ai-copy">
      <span>✦ INTELIGENCIA ENERGÉTICA · {dashboardPeriodLabel.toUpperCase()}</span>
      <h2>¿Qué querés saber del período?</h2>
      <p>Preguntale a la IA sobre consumo, facturas faltantes, potencia, cos φ y oportunidades de ahorro del mes.</p>
    </div>
    <div className="dashboard-ai-query">
      <input
        value={aiQuery}
        onChange={e=>setAiQuery(e.target.value)}
        onKeyDown={e=>{if(e.key==="Enter"){setTab("ai");runAiQuery()}}}
        placeholder={`Ej.: ¿Qué debería revisar primero en ${dashboardPeriodLabel}?`}
      />
      <button onClick={()=>{setTab("ai");runAiQuery()}} disabled={aiBusy}>
        {aiBusy?"Analizando…":"Preguntar a IA"}
      </button>
    </div>
  </section>

  <div className="dashboard-month-kpis">
    <article className="received">
      <span>Facturas recibidas</span>
      <strong>{dashboardReceived} <i>/ {activeMeters.length}</i></strong>
      <small>{dashboardPeriodLabel}</small>
    </article>
    <article className={dashboardMissing.length?"missing":"ok"}>
      <span>Faltantes de agosto</span>
      <strong>{dashboardMissing.length}</strong>
      <small>{dashboardMissing.length?"requieren seguimiento":"período completo"}</small>
    </article>
    <article className="opportunities">
      <span>Suministros con oportunidad</span>
      <strong>{dashboardOpportunityIds.size}</strong>
      <small>{dashboardLowPf} cos φ bajo · {dashboardPowerExcess} con potencia sobrante</small>
    </article>
    <article className="saving">
      <span>Ahorro mensual potencial</span>
      <strong>{money.format(dashboardTotalMonthly)}</strong>
      <small>{money.format(dashboardTotalAnnual)} anual · potencia según curva mensual</small>
    </article>
  </div>

  <div className="dashboard-period-strip">
    <b>Situación de {dashboardPeriodLabel}</b>
    <span>{dashboardMissing.length} facturas faltantes</span>
    <span>{dashboardOpportunityIds.size} suministros con oportunidad</span>
    <span>{dashboardLowPf} con cos φ bajo</span>
    <span>{dashboardPowerExcess} con potencia sobrante</span>
  </div>

  <section className="panel executive-savings">
    <Title
      title={`Desglose del ahorro potencial · ${dashboardPeriodLabel}`}
      sub={`Potencia: curva mensual histórica por suministro. Factor de potencia y tarifa: proyección mensual × 12. Valores con 30% de IVA donde corresponde.`}
    />
    <div className="dashboard-savings-grid">
      <article className="power">
        <span>Potencia contratada</span>
        <strong>{money.format(dashboardPowerAnnual)}</strong>
        <small>{money.format(dashboardPowerMonthly)} mensual · {dashboardPeriodLabel}</small>
        <p>Curva anual: para cada mes toma la mayor demanda del mismo mes entre los años disponibles, contra la última potencia contratada.</p>
      </article>
      <article className="reactive">
        <span>Factor de potencia</span>
        <strong>{money.format(dashboardReactiveMonthly*12)}</strong>
        <small>{money.format(dashboardReactiveMonthly)} mensual · {dashboardPeriodLabel}</small>
        <p>Recargos de energía reactiva evitables detectados en el mes.</p>
      </article>
      <article className="rate">
        <span>Cambio tarifario</span>
        <strong>{money.format(dashboardRateMonthly*12)}</strong>
        <small>{money.format(dashboardRateMonthly)} mensual · {dashboardPeriodLabel}</small>
        <p>{advancedTariffSummary?.billing_period===dashboardPeriod?`Cambio tarifario valorizado · ${dashboardTariffValuedCount} suministro(s) · incluye T3/T3A→T4 y BT→MT.`:"Diferencia contra la categoría recomendada para ese período."}</p>
      </article>
      <article className="saving-total">
        <span>Ahorro total propuesto</span>
        <strong>{money.format(dashboardTotalAnnual)}</strong>
        <small>{money.format(dashboardTotalMonthly)} mensual · {dashboardPeriodLabel}</small>
        <p>Potencia anual según curva de 12 meses; los demás ahorros se anualizan desde el período actual.</p>
      </article>
    </div>
  </section>
</>}
  {tab==="invoices"&&<>
  <div className="invoice-subtabs">
    <button className={invoiceSubTab==="received"?"active":""} onClick={()=>setInvoiceSubTab("received")}>
      <span>Facturas recibidas</span>
      <b>{dashboardReceived}</b>
    </button>
    <button className={invoiceSubTab==="missing"?"active missing":""} onClick={()=>setInvoiceSubTab("missing")}>
      <span>Sin facturación reciente</span>
      <b>{lifecycleMeters.length}</b>
    </button>
    <button className={invoiceSubTab==="publicLighting"?"active":""} onClick={()=>setInvoiceSubTab("publicLighting")}>
      <span>Alumbrado público</span>
      <b>AP</b>
    </button>
  </div>

  {invoiceSubTab==="received"&&<>

<section className="month-control"><div><span>Período controlado</span><strong>{controlPeriod||"Sin período"}</strong></div><div><span>Facturas esperadas</span><strong>{activeMeters.length}</strong></div><div className="received"><span>Facturas recibidas</span><strong>{[...presentMeterIds].filter(id=>activeMeters.some(m=>m.id===id)).length}</strong></div><div className={missingPeriodMeters.length?"missing":"complete"}><span>Faltantes de agosto</span><strong>{missingPeriodMeters.length}</strong></div></section>
{missingPeriodMeters.length>0&&<section className="panel missing-invoice-panel"><Title title={`Faltan ${missingPeriodMeters.length} facturas de ${controlPeriod}`} sub="Estos medidores no aparecen en el archivo del período seleccionado"/><div className="missing-meter-grid">{missingPeriodMeters.map(m=><article key={m.id}><i>!</i><div><b>Medidor {m.meter_number||"S/D"}</b><span>{m.service_name||m.sites?.name||"Servicio sin nombre"}</span><small>{m.tracking_code} · Suministro {m.supply_number||"S/D"}</small></div></article>)}</div></section>}<section className="panel"><Title title="Administrador mensual y anual" sub={`${filteredInvoices.length} de ${meters.length} facturas recibidas para ${controlPeriod}`}/><div className="filters"><label>Año<select value={yearFilter} onChange={e=>setYearFilter(e.target.value)}>{years.map(y=><option key={y}>{y}</option>)}</select></label><label>Mes<select value={monthFilter} onChange={e=>setMonthFilter(e.target.value)}>{Array.from({length:12},(_,i)=>String(i+1).padStart(2,"0")).map(m=><option key={m} value={m}>{new Date(2026,Number(m)-1,1).toLocaleString("es-AR",{month:"long"})}</option>)}</select></label><label className="search-filter">Buscar<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Medidor, suministro, servicio o factura"/></label><button onClick={()=>setSearch("")}>Limpiar búsqueda</button></div><div className="invoice-unified-scroll"><InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} epenOptimization={epenOptimization} advancedTariffSummary={advancedTariffSummary} pendingMeters={visibleMissingPeriodMeters} period={controlPeriod} onSelect={openMeter} onSelectMeter={openMeterById}/></div></section>{selectedInvoice&&<InvoiceAnalysisPanel invoice={selectedInvoice} history={invoices.filter(x=>x.meter_id===selectedInvoice.meter_id)} tariffSavings={tariffSavings} assessment={assessments.find(x=>x.meter_id===selectedInvoice.meter_id)} optimization={epenOptimization.find(x=>x.meter_id===selectedInvoice.meter_id)} onClose={()=>setSelectedInvoice(null)}/>}
  </>}

  {invoiceSubTab==="missing"&&<div className="invoice-missing-subpage">
    <section className="panel invoice-missing-summary">
      <div>
        <span>POSIBLES BAJAS / SIN FACTURACIÓN RECIENTE</span>
        <h2>Posibles bajas y medidores sin facturación reciente</h2>
        <p>Acá se muestran los medidores que llevan varios meses sin facturación y requieren definir si continúan activos o corresponden a una baja.</p>
      </div>
      <div className="invoice-missing-total">
        <b>{lifecycleMeters.length}</b>
        <small>posibles bajas / seguimiento</small>
      </div>
    </section>

    <section className="panel invoice-missing-list-panel">
      <div className="invoice-missing-list-head">
        <span>Estado</span>
        <span>Medidor / ID</span>
        <span>Servicio</span>
        <span>Suministro</span>
        <span>Última factura</span>
        <span>Meses sin factura</span>
        <span>Acciones</span>
      </div>

      <div className="invoice-missing-list-body">
        {lifecycleMeters.map(m=>{
          const months=monthsBetween(m.last_seen_period,periods[0]||"");
          return <div className={`invoice-missing-list-row ${m.status==="removed"?"removed":"watch"}`} key={m.id}>
            <div><span className={`invoice-missing-state ${m.status||"inactive"}`}>{m.status==="removed"?"BAJA CONFIRMADA":"POSIBLE BAJA"}</span></div>
            <div><b>Medidor {m.meter_number||"S/D"}</b><small>{m.tracking_code||"Sin ID"}</small></div>
            <div><b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b><small>{m.sites?.address||"Sin dirección registrada"}</small></div>
            <div><b>{m.supply_number||"S/D"}</b><small>{m.current_tariff_code||"Sin tarifa"}</small></div>
            <div><b>{m.last_seen_period?.slice(0,7)||"S/D"}</b><small>último período cargado</small></div>
            <div><b>{months}</b><small>meses</small></div>
            <div className="invoice-missing-list-actions">
              {m.status!=="removed"&&<button className="danger-btn" onClick={()=>updateMeterStatus(m.id,"removed")}>Confirmar baja</button>}
              <button className="ok-btn" onClick={()=>updateMeterStatus(m.id,"active")}>Continúa activo</button>
            </div>
          </div>
        })}
        {!lifecycleMeters.length&&<div className="invoice-missing-list-empty">No hay medidores sin facturación reciente.</div>}
      </div>
    </section>
  </div>}
  {invoiceSubTab==="publicLighting"&&<PublicLightingPanel
  session={session}
  organizationId={orgId||""}
  invoices={invoices}
  tariffSavings={tariffSavings}
  epenOptimization={epenOptimization}
/>}
</>}{tab==="framing"&&<><EpenOptimizationPanel session={session} organizationId={orgId||""} onOpenMeter={openMeterById}/><div className="savings-summary"><article><span>Potencia contratada</span><b>{money.format(powerAnnual)}</b><small>ahorro anual</small></article>
<article><span>Factor de potencia</span><b>{money.format(reactiveAnnual)}</b><small>recargos evitables</small></article>
<article><span>Cambio tarifario</span><b>{money.format(rateAnnual)}</b><small>ahorro anual simulado</small></article><article className="total"><span>Total de propuestas</span><b>{money.format(tariffAnnual)}</b><small>{money.format(tariffAnnual/12)} por mes</small></article></div><div className="framing-meta"><span>{assessments.length} suministros analizados</span><span>{reviewCount} requieren revisión</span><span>{assessments.filter(x=>x.status==="correct").length} correctamente encuadrados</span></div><TariffSavingsTable rows={tariffSavings}/><section className="panel"><Title title="Diagnóstico y ahorros separados" sub="Potencia · Energía reactiva · Categoría tarifaria"/><div className="framing-tabs"><button className={framingFilter==="all"?"active":""} onClick={()=>setFramingFilter("all")}>Todos</button><button className={framingFilter==="change_candidate"?"active":""} onClick={()=>setFramingFilter("change_candidate")}>Posible cambio</button><button className={framingFilter==="power_review"?"active":""} onClick={()=>setFramingFilter("power_review")}>Revisar potencia</button><button className={framingFilter==="provisional"?"active":""} onClick={()=>setFramingFilter("provisional")}>Provisorios</button><button className={framingFilter==="correct"?"active":""} onClick={()=>setFramingFilter("correct")}>Correctos</button></div><TariffTable rows={visibleAssessments} onMeter={id=>{const i=invoices.find(x=>x.meter_id===id);if(i)openMeter(i)}}/></section>{selectedInvoice&&<InvoiceAnalysisPanel invoice={selectedInvoice} history={invoices.filter(x=>x.meter_id===selectedInvoice.meter_id)} tariffSavings={tariffSavings} assessment={assessments.find(x=>x.meter_id===selectedInvoice.meter_id)} optimization={epenOptimization.find(x=>x.meter_id===selectedInvoice.meter_id)} onClose={()=>setSelectedInvoice(null)}/>}</>}
  {tab==="tariffs"&&<HistoricalAnalysis invoices={invoices} meters={meters} tariffSavings={tariffSavings}/>}
    {tab==="ai"&&<div className="ai-module">
    <section className="panel ai-hero">
      <div>
        <span className="ai-kicker">ASISTENTE DE GESTIÓN ENERGÉTICA</span>
        <h2>IA para analizar la base municipal</h2>
        <p>Consultá facturas, consumo, potencia, factor de potencia, faltantes y oportunidades de ahorro.</p>
      </div>
      <div className="ai-badge">✦ IA</div>
    </section>

    <section className="panel ai-chat">
      <div className="ai-chat-head">
        <div><h2>Preguntale a la base</h2><p>Conectado al backend, Supabase y OpenAI.</p></div>
      </div>

      <div className="ai-suggestions">
        {[
          "¿Qué 5 acciones me hacen ahorrar más este mes?",
          "¿Qué suministros parecen estar sobredimensionados?",
          "¿Qué suministros podrían estar fuera de uso?",
          "¿Dónde tengo penalización por factor de potencia?",
          "¿Qué consumos aumentaron anormalmente este mes?"
        ].map(q=><button key={q} onClick={()=>{setAiQuery(q);runAiQuery(q)}}>{q}</button>)}
      </div>

      <div className="ai-answer">
        <div className="ai-avatar">✦</div>
        <div className="ai-answer-content"><b>Asistente energético</b><div className="ai-rich-response">{aiBusy?<p className="ai-rich-paragraph">Analizando Supabase con OpenAI…</p>:renderAiRichText(aiAnswer,openAiReference)}</div></div>
      </div>

      <div className="ai-input-row">
        <input value={aiQuery} onChange={e=>setAiQuery(e.target.value)} onKeyDown={e=>{if(e.key==="Enter")runAiQuery()}} placeholder="Ej.: ¿Qué 5 acciones concretas debería hacer primero para ahorrar este mes?"/>
        <button onClick={()=>runAiQuery()} disabled={aiBusy}>{aiBusy?"Analizando…":"Consultar"}</button>
      </div>
    </section>

    <div className="ai-alert-grid">
      <article><span>Faltantes de agosto</span><b>{missingPeriodMeters.length}</b><small>{controlPeriod||periods[0]||"Sin período"}</small></article>
      <article><span>Cos φ bajo</span><b>{latestInvoiceByMeter.filter(i=>{const p=metrics(i).pf;return p>0&&p<.95}).length}</b><small>requieren revisión</small></article>
      <article><span>Potencia sobrante</span><b>{latestInvoiceByMeter.filter(i=>metrics(i).excess>0).length}</b><small>medidores detectados</small></article>
      <article className="green"><span>Ahorro anual potencial</span><b>{money.format(dashboardTotalMonthly*12)}</b><small>{dashboardPeriodLabel} · mensual {money.format(dashboardTotalMonthly)}</small></article>
    </div>

        <div className="ai-smart-sections">
      <section className="panel ai-smart-card critical">
        <div className="ai-smart-head"><div><span>ALERTAS CRÍTICAS</span><h3>Qué revisar ahora</h3></div><b>{aiAlertData.criticalCount}</b></div>
        <div className="ai-smart-list">
          {aiAlertData.critical.length?aiAlertData.critical.map((a,index)=><button key={`${a.kind}-${index}`} className="ai-alert-clickable" title="Abrir análisis del medidor" onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>
            <i>!</i><div><b>{a.label}</b><span>{a.detail}</span></div><em>Revisar</em>
          </button>):<div className="ai-smart-empty">No hay alertas críticas para el último período.</div>}
        </div>
      </section>

      <section className="panel ai-smart-card opportunities">
        <div className="ai-smart-head"><div><span>TOP OPORTUNIDADES</span><h3>Dónde hay más ahorro</h3></div><b>{aiAlertData.opportunityCount}</b></div>
        <div className="ai-smart-list">
          {aiAlertData.opportunities.length?aiAlertData.opportunities.map((a,index)=><button key={`${a.kind}-${index}`} className="ai-alert-clickable" title="Abrir análisis del medidor" onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>
            <i>$</i><div><b>{a.label}</b><span>{a.detail}</span></div><em>{money.format(a.value)}</em>
          </button>):<div className="ai-smart-empty">No hay oportunidades valorizadas en el último período.</div>}
        </div>
      </section>

      <section className="panel ai-smart-card changes">
        <div className="ai-smart-head"><div><span>QUÉ CAMBIÓ ESTE MES</span><h3>Variaciones relevantes</h3></div><b>{aiAlertData.changes.length}</b></div>
        <div className="ai-smart-list">
          {aiAlertData.changes.length?aiAlertData.changes.map((a,index)=><button key={index} className="ai-alert-clickable" title="Abrir análisis del medidor" onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>
            <i>{a.positive?"↓":"↕"}</i><div><b>{a.label}</b><span>{a.detail}</span></div><em className={a.positive?"positive":""}>{a.positive?"Mejora":"Cambio"}</em>
          </button>):<div className="ai-smart-empty">No se detectaron cambios superiores al 20% contra el mes anterior.</div>}
        </div>
      </section>
    </div>
  </div>}
{tab==="map"&&session&&orgId&&<MetersMap session={session} organizationId={orgId} meters={meters} invoices={invoices} onOpenMeter={openMeterById}/>}
  </section>{toast&&<div className="toast">{toast}</div>}</main>;
}

function Title({title,sub,action}:{title:string;sub:string;action?:()=>void}){return <div className="panel-title"><div><h2>{title}</h2><p>{sub}</p></div>{action&&<button onClick={action}>Ver todas →</button>}</div>}
function hashText(value:string){let h=0;for(let i=0;i<value.length;i++)h=(h*31+value.charCodeAt(i))>>>0;return h}
function invoiceReactiveSaving(i:Invoice){return (i.invoice_lines||[]).filter(x=>x.concept_code==="COS").reduce((s,x)=>s+Math.max(0,Number(x.net_amount||0)),0)*1.30}
function minimumContractedKw(tariff?:string){const code=String(tariff||"").toUpperCase().replace(/[^A-Z0-9]/g,"");return code.startsWith("T3")?50:code.startsWith("T2")?10:0}
function invoicePowerSaving(i:Invoice){const lines=i.invoice_lines||[],powerLines=lines.filter(x=>x.concept_code==="DEM"||x.concept_code==="DEP"),billed=Math.max(0,...powerLines.map(x=>Number(x.quantity||0))),contracted=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||billed),demand=Math.max(0,...(i.invoice_measurements||[]).map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0))),proposed=Math.max(demand,minimumContractedKw(i.current_tariff_code||i.meters?.current_tariff_code)),units=Math.max(0,contracted-proposed),rate=Math.max(0,...powerLines.map(x=>Number(x.unit_price||0))),amount=units*rate*1.30;return{units,rate,amount}}
function metrics(i:Invoice){
  const ms=i.invoice_measurements||[];
  const kwh=ms.reduce((s,m)=>s+Number(m.active_energy_kwh||0),0);
  const demand=Math.max(0,...ms.map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));
  const contracted=Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||Math.max(0,...(i.invoice_lines||[]).filter(x=>x.concept_code==="DEM"||x.concept_code==="DEP").map(x=>Number(x.quantity||0))));
  const pfs=ms.map(m=>Number(m.resolved_power_factor||m.power_factor||0)).filter(v=>v>0);
  const pf=pfs.length?Math.min(...pfs):Number(i.resolved_power_factor||0);
  const surcharge=Math.max(0,...ms.map(m=>Number(m.reactive_surcharge_percent||0)));
  const cosCharge=(i.invoice_lines||[]).filter(x=>String(x.concept_code||"").toUpperCase()==="COS").reduce((s,x)=>s+Math.max(0,Number(x.net_amount||0)),0);
  const penalized=Boolean(i.power_factor_penalized)||ms.some(m=>m.power_factor_penalized)||surcharge>0||cosCharge>0;
  const minimumKw=minimumContractedKw(i.current_tariff_code||i.meters?.current_tariff_code);
  const proposed=Math.max(demand,minimumKw);
  return{kwh,demand,contracted,excess:Math.max(0,contracted-proposed),minimumKw,proposed,pf,surcharge,penalized};
}
function InvoiceTable({invoices,assessments,tariffSavings,epenOptimization,advancedTariffSummary,pendingMeters,period,onSelect,onSelectMeter}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];epenOptimization:EpenOptimizationMeter[];advancedTariffSummary:AdvancedTariffSummary|null;pendingMeters:Meter[];period:string;onSelect?:(i:Invoice)=>void;onSelectMeter?:(meterId:string)=>void}){const[sort,setSort]=useState<"consumption"|"demand"|"contracted"|"excess"|"pf"|"tariff"|null>(null),[direction,setDirection]=useState<"asc"|"desc">("asc"),order=(field:"consumption"|"demand"|"pf"|"tariff")=>{if(sort===field)setDirection(x=>x==="asc"?"desc":"asc");else{setSort(field);setDirection(field==="consumption"||field==="demand"?"desc":"asc")}},orderPower=()=>{setSort(x=>x==="contracted"?"excess":"contracted");setDirection("desc")},value=(i:Invoice)=>sort==="consumption"?metrics(i).kwh:sort==="demand"?metrics(i).demand:sort==="contracted"?metrics(i).contracted:sort==="excess"?metrics(i).excess:sort==="pf"?metrics(i).pf:(i.current_tariff_code||""),sorted=[...invoices].sort((a,b)=>{if(!sort)return 0;if(sort==="pf"){const ap=metrics(a).pf,bp=metrics(b).pf,ar=ap<=0?2:ap<.95?0:1,br=bp<=0?2:bp<.95?0:1;if(ar!==br)return ar-br;if(ar===2)return 0;return direction==="asc"?ap-bp:bp-ap}const av=value(a),bv=value(b),result=typeof av==="string"?av.localeCompare(String(bv),"es",{numeric:true}):Number(av)-Number(bv);return direction==="asc"?result:-result}),head=(field:"consumption"|"demand"|"pf"|"tariff",label:string)=><button className="sort-head" onClick={()=>order(field)}>{label}<i>{sort===field?(direction==="asc"?"▲":"▼"):"↕"}</i></button>,powerHead=<button className="sort-head power-sort" onClick={orderPower}><span>Contratada / sobrante<small>{sort==="contracted"?"Orden: potencia contratada":sort==="excess"?"Orden: mayor sobrante":"Tocar para ordenar"}</small></span><i>{sort==="contracted"?"kW ▼":sort==="excess"?"SOB ▼":"↕"}</i></button>;return <div className="table invoice-admin-scroll"><table className="invoice-admin"><thead><tr><th>Medidor / ID</th><th>Servicio</th><th>Mes facturado</th><th>{head("consumption","Consumo")}</th><th>{head("demand","Potencia registrada")}</th><th>{powerHead}</th><th><button className={`sort-head pf-sort-head ${sort==="pf"?"active":""}`} onClick={()=>order("pf")}><span>Factor potencia<small>{sort==="pf"?(direction==="asc"?"Malos primero · peor → mejor":"Malos primero · mejor → peor"):"Tocar: FP < 0,95 primero"}</small></span><i>{sort==="pf"?(direction==="asc"?"⚠ ▲":"⚠ ▼"):"↕"}</i></button></th><th>{head("tariff","Tarifa")}</th><th>Medidas de ahorro</th><th>Ahorro anual estimado</th><th>Importe factura</th></tr></thead><tbody>{sorted.map(i=>{const x=metrics(i),bad=x.pf>0&&x.pf<.95,period=(i.billing_period||i.period_start).slice(0,7),tariffResult=tariffSavings.find(t=>t.meter_id===i.meter_id&&String(t.billing_period).slice(0,7)===period),advanced=epenOptimization.find(e=>e.meter_id===i.meter_id),candidate=assessments.find(a=>a.meter_id===i.meter_id),assessment=candidate&&(!candidate.billing_period||candidate.billing_period.slice(0,7)===period)?candidate:undefined,power=invoicePowerSaving(i),powerSaving=power.amount||Number(assessment?.power_monthly_saving||0),invoiceReactive=invoiceReactiveSaving(i),reactiveSaving=invoiceReactive||Number(assessment?.reactive_monthly_saving||0),advancedTariffRow=advancedTariffSummary?.billing_period===period?advancedTariffSummary.meters.find(t=>(t.meter_id===i.meter_id||String((t as any).meter_number||"")===String(i.meters?.meter_number||"")||String((t as any).supply_number||"")===String(i.meters?.supply_number||""))&&String(t.billing_period).slice(0,7)===period&&t.available):undefined,advancedSummarySaving=Number(advancedTariffRow?.monthly_saving||0),optimizationMtSaving=advanced&&["strong","candidate","preliminary"].includes(advanced.mt.status)?Number(advanced.mt.monthly_saving_before_taxes||0):0,optimizationT4Saving=advanced?.t4.status==="candidate"?Number(advanced.t4.monthly_saving_before_taxes||0):0,advancedTariffSaving=advancedSummarySaving>0?advancedSummarySaving:optimizationMtSaving>0?optimizationMtSaving:optimizationT4Saving,legacyTariffSaving=Math.max(Number(tariffResult?.monthly_saving_with_vat||0),Number(assessment?.tariff_monthly_saving||0),Math.max(0,Number(assessment?.tariff_current_simulated||0)-Number(assessment?.tariff_recommended_simulated||0))),tariffSaving=advancedTariffSaving>0?advancedTariffSaving:legacyTariffSaving,advancedTariffLabel=advancedSummarySaving>0?`${advancedTariffRow?.current_tariff||"Tarifa"} → ${advancedTariffRow?.recommended_tariff||"Propuesta"}`:optimizationMtSaving>0?`${String(i.current_tariff_code||i.meters?.current_tariff_code||"Tarifa")}-BT → ${String(i.current_tariff_code||i.meters?.current_tariff_code||"Tarifa")}-MT`:optimizationT4Saving>0?`${String(i.current_tariff_code||i.meters?.current_tariff_code||"T3")}-${String(i.voltage_level||i.meters?.voltage_level||"MT")} → ${advanced?.t4.target_tariff||"T4"}`:"Tarifaria",estimatedSaving=powerSaving+reactiveSaving+tariffSaving,measures=[powerSaving>0?"Potencia contratada":"",tariffSaving>0?(advancedTariffSaving>0?advancedTariffLabel:"Tarifaria"):"",reactiveSaving>0?"Factor de potencia":""].filter(Boolean);return <tr key={i.id} className={`selectable${bad?" pf-problem-row":""}`} onClick={()=>onSelect?.(i)}><td><b>Medidor {i.meters?.meter_number||"S/D"}</b><small>{i.meters?.tracking_code||"Sin ID"}</small></td><td><b>{i.meters?.service_name||i.meters?.sites?.name||"Servicio sin nombre"}</b><small>Suministro {i.meters?.supply_number||"S/D"}</small></td><td><b>{(i.billing_period||i.period_start).slice(0,7)}</b><small>Factura {i.invoice_number||"S/D"}</small></td><td><b>{number.format(x.kwh)} kWh</b></td><td><b>{number.format(x.demand)} kW</b></td><td><b>{number.format(x.contracted)} kW</b><small className={x.excess>0?"danger":"ok"}>{x.excess>0?`${number.format(x.excess)} kW de más`:"Sin potencia sobrante"}</small></td><td>{x.pf?<span className={`status-pill ${bad?"bad":"good"}`}>{x.pf.toFixed(3)} {bad?"Bajo":"Correcto"}</span>:x.penalized?<span className="status-pill bad">Penalizado · FP S/D</span>:<span className="status-pill neutral">No detectado</span>} {x.surcharge>0&&<small className="danger">Recargo {x.surcharge}%</small>}</td><td><div className="tariff-advanced-cell"><div><span className="tag low">{i.current_tariff_code||"S/D"}</span><small>{tariffResult&&tariffResult.current_tariff!==tariffResult.recommended_tariff?<>{tariffResult.current_tariff} → {tariffResult.recommended_tariff}</>:(i.voltage_level||i.meters?.voltage_level)}</small></div>{advanced&&<div className="tariff-advanced-badges">{advanced.t3.status==="candidate"&&<span className="t3-dual">T3 · 2 POTENCIAS</span>}{advanced.t4.status==="candidate"&&<span className="t4-candidate">APTO T4</span>}{["strong","candidate","preliminary"].includes(advanced.mt.status)&&<span className="mt-candidate">BT → MT</span>}</div>}</div></td><td><div className={measures.length?"saving-measures active":"saving-measures"}>{measures.length?<b>{measures.join(" + ")}</b>:<small>Sin ahorro detectado</small>}</div></td><td>{estimatedSaving>0?<strong className="row-saving">{money.format(estimatedSaving*12)}<small>{money.format(estimatedSaving)} mensual × 12{advancedTariffSaving>0?" · tarifa antes de impuestos":""}</small></strong>:<small>—</small>}</td><td><strong className="save">{money.format(Number(i.total_amount||0))}</strong><small>Ver detalle →</small></td></tr>})}{pendingMeters.length>0&&<><tr className="pending-section-row"><td colSpan={11}><div className="pending-section-content"><b>Facturas pendientes del período</b><span>{pendingMeters.length} filas pendientes</span></div></td></tr>{pendingMeters.map(m=>{const possibleRemoval=m.status==="inactive";return <tr key={`pending-${m.id}`} className={`pending-invoice-row selectable${possibleRemoval?" possible-removal":""}`} onClick={()=>onSelectMeter?.(m.id)} title="Abrir análisis histórico del medidor"><td><b>Medidor {m.meter_number||"S/D"}</b><small>{m.tracking_code||"Sin ID"}</small></td><td><b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b><small>Suministro {m.supply_number||"S/D"}</small></td><td><b>{period}</b><small>Factura faltante</small></td><td colSpan={7}><div className="pending-placeholder">{possibleRemoval?"Sin facturación reciente: posible baja, aún debe solicitarse la factura":`No se cargó una factura para este medidor en ${period}`}</div></td><td><span className="pending-badge">{possibleRemoval?"POSIBLE BAJA · PENDIENTE":"PENDIENTE"}<small>Ver análisis →</small></span></td></tr>})}</>}{!invoices.length&&!pendingMeters.length&&<tr><td colSpan={11}><div className="empty">No hay facturas para los filtros seleccionados.</div></td></tr>}</tbody></table></div>}

function TariffTable({rows,onMeter}:{rows:TariffAssessment[];onMeter:(id:string)=>void}){const labels={correct:"Correcto",power_review:"Revisar potencia",change_candidate:"Posible cambio",provisional:"Provisorio"},[sort,setSort]=useState<"power"|"pf"|"tariff"|"saving"|null>(null),[direction,setDirection]=useState<"asc"|"desc">("asc");const order=(field:"power"|"pf"|"tariff"|"saving")=>{if(sort===field)setDirection(x=>x==="asc"?"desc":"asc");else{setSort(field);setDirection("asc")}},value=(x:TariffAssessment)=>sort==="power"?x.contracted_kw:sort==="pf"?(x.power_factor??-1):sort==="tariff"?(x.current_tariff||""):x.estimated_monthly_saving,sorted=[...rows].sort((a,b)=>{if(!sort)return 0;const av=value(a),bv=value(b),result=typeof av==="string"?av.localeCompare(String(bv),"es",{numeric:true}):Number(av)-Number(bv);return direction==="asc"?result:-result}),head=(field:"power"|"pf"|"tariff"|"saving",label:string)=><button className="sort-head" onClick={()=>order(field)}>{label}<i>{sort===field?(direction==="asc"?"▲":"▼"):"↕"}</i></button>;return <div className="table"><table className="tariff-table split-savings"><thead><tr><th>Medidor / servicio</th><th>{head("power","Potencia contratada")}</th><th>{head("pf","Factor de potencia")}</th><th>{head("tariff","Tarifa y posible arreglo")}</th><th>Diagnóstico</th><th>{head("saving","Total propuesto")}</th></tr></thead><tbody>{sorted.map(x=><tr key={x.meter_id} className="selectable" onClick={()=>onMeter(x.meter_id)}><td><b>{x.meter.service_name||"Servicio sin nombre"}</b><small>Medidor {x.meter.meter_number} · {x.meter.tracking_code}</small><small>{x.periods_analyzed} período{x.periods_analyzed===1?"":"s"} · Confianza {x.confidence}%</small></td><td><b>{x.contracted_kw} kW → {x.recommended_kw} kW</b><small>Máxima registrada: {x.maximum_demand_kw} kW</small><Saving value={x.power_monthly_saving}/></td><td><b>{x.power_factor?x.power_factor.toFixed(3):"No detectado"}</b><small>{x.power_factor&&x.power_factor<.95?"Corregir banco de capacitores":"Sin penalización detectada"}</small><Saving value={x.reactive_monthly_saving}/></td><td><div><span className="tariff-code">{x.current_tariff||"S/D"}</span><b className="arrow">→</b><span className={x.current_tariff===x.recommended_tariff?"tariff-code same":"tariff-code recommended"}>{x.recommended_tariff}</span></div><small>{x.official_schedule?`Cuadro EPEN ${x.official_schedule.resolution_number} · vigencia ${x.official_schedule.valid_from} a ${x.official_schedule.valid_to}`:x.tariff_simulation_available?"Estimación con precios observados":"Falta cuadro tarifario del período"}</small><Saving value={x.tariff_monthly_saving}/>{x.tariff_simulation_available&&x.tariff_current_simulated!=null&&x.tariff_recommended_simulated!=null&&<small>Costo vigente: {money.format(x.tariff_current_simulated)} → {money.format(x.tariff_recommended_simulated)}</small>}</td><td><span className={`assessment ${x.status}`}>{labels[x.status]}</span><p className="assessment-reason">{x.reasons.join(" · ")}</p></td><td><strong className="grand-saving">{money.format(x.estimated_monthly_saving)}<small>/mes</small></strong><small>{money.format(x.estimated_annual_saving)} /año</small></td></tr>)}{!rows.length&&<tr><td colSpan={6}><div className="empty">No hay suministros en esta categoría.</div></td></tr>}</tbody></table></div>}
function TariffSavingsTable({rows}:{rows:TariffSaving[]}){if(!rows.length)return null;return <section className="panel tariff-savings-panel"><Title title="Cambios tarifarios valorizados" sub={`${rows.filter(x=>Number(x.monthly_saving_with_vat)>0).length} con ahorro positivo · ${rows.length} candidatos`}/><div className="table"><table><thead><tr><th>Medidor / servicio</th><th>Período</th><th>Cambio propuesto</th><th>Potencia usada</th><th>Costo tarifa actual</th><th>Costo recomendado</th><th>Ahorro mensual</th><th>Ahorro anual</th></tr></thead><tbody>{rows.map(x=><tr key={x.meter_id}><td><b>{x.service_name||"Servicio sin nombre"}</b><small>Medidor {x.meter_number} · Suministro {x.supply_number||"S/D"}</small></td><td>{String(x.billing_period).slice(0,7)}</td><td><span className="tariff-code">{x.current_tariff}</span><b className="arrow">→</b><span className="tariff-code recommended">{x.recommended_tariff}</span></td><td><b>{number.format(Number(x.used_kw||0))} kW</b></td><td>{money.format(Number(x.current_cost_with_vat||0))}</td><td>{money.format(Number(x.recommended_cost_with_vat||0))}</td><td><strong className={Number(x.monthly_saving_with_vat)>0?"save":"muted-saving"}>{money.format(Number(x.monthly_saving_with_vat||0))}</strong></td><td><strong className={Number(x.annual_saving_with_vat)>0?"save":"muted-saving"}>{money.format(Number(x.annual_saving_with_vat||0))}</strong></td></tr>)}</tbody></table></div></section>}

function monthsBetween(from?:string,to?:string){if(!from||!to)return 0;const[a,b]=from.slice(0,7).split("-").map(Number),[c,d]=to.slice(0,7).split("-").map(Number);return Math.max(0,(c-a)*12+d-b)}
function MeterLifecyclePanel({meters,latestPeriod,onStatus}:{meters:Meter[];latestPeriod:string;onStatus:(id:string,status:"active"|"inactive"|"removed")=>void}){if(!meters.length)return null;return <section className="panel lifecycle-panel"><Title title="Sin facturación recienteción reciente" sub="Se controlan por separado y no se cuentan como facturas faltantes"/><div className="lifecycle-grid">{meters.map(m=><article key={m.id} className={m.status==="removed"?"removed":"watch"}><div className="lifecycle-icon">{m.status==="removed"?"×":"!"}</div><div className="lifecycle-info"><span className={`lifecycle-status ${m.status}`}>{m.status==="removed"?"BAJA CONFIRMADA":"POSIBLE BAJA"}</span><b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b><small>Medidor {m.meter_number||"S/D"} · Suministro {m.supply_number||"S/D"}</small><dl><div><dt>Última factura</dt><dd>{m.last_seen_period?.slice(0,7)||"S/D"}</dd></div><div><dt>Meses sin factura</dt><dd>{monthsBetween(m.last_seen_period,latestPeriod)}</dd></div></dl></div><div className="lifecycle-actions">{m.status!=="removed"&&<button className="confirm-remove" onClick={()=>onStatus(m.id,"removed")}>Confirmar baja</button>}<button className="keep-active" onClick={()=>onStatus(m.id,"active")}>Continúa activo</button></div></article>)}</div></section>}

function MissingInvoiceTable({meters,period}:{meters:Meter[];period:string}){if(!meters.length)return null;return <div className="missing-table"><div className="missing-table-title"><b>Facturas pendientes del período</b><span>{meters.length} filas pendientes</span></div><table className="invoice-admin"><tbody>{meters.map(m=>{const possibleRemoval=m.status==="inactive";return <tr key={m.id} className={`missing-invoice-row${possibleRemoval?" possible-removal":""}`} style={possibleRemoval?{background:"#fff4c2"}:undefined}><td><b>Medidor {m.meter_number||"S/D"}</b><small>{m.tracking_code||"Sin ID"}</small></td><td><b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b><small>Suministro {m.supply_number||"S/D"}</small></td><td><b>{period}</b><small>Factura faltante</small></td><td colSpan={7}><div className="missing-placeholder">{possibleRemoval?"Sin facturación reciente: posible baja, aún debe solicitarse la factura":`No se cargó una factura para este medidor en ${period}`}</div></td><td><span className="missing-badge">{possibleRemoval?"POSIBLE BAJA · PENDIENTE":"PENDIENTE"}</span></td></tr>})}</tbody></table></div>}

function Saving({value}:{value:number}){return <div className={value>0?"saving-chip positive":"saving-chip"}><span>{money.format(value)}</span><small>/mes</small></div>}

function MeterDetail({invoice,history,onClose}:{invoice:Invoice;history:Invoice[];onClose:()=>void}){const m=invoice.meters,x=metrics(invoice),sorted=[...history].sort((a,b)=>(b.billing_period||b.period_start).localeCompare(a.billing_period||a.period_start));return <div className="detail-backdrop" onClick={onClose}><aside className="meter-detail" onClick={e=>e.stopPropagation()}><div className="detail-head"><div><small>DETALLE DEL MEDIDOR</small><h2>{m?.service_name||m?.sites?.name||"Servicio sin nombre"}</h2><p>{m?.tracking_code} · Medidor {m?.meter_number}</p></div><button onClick={onClose}>×</button></div><div className="detail-kpis"><article><span>Consumo del mes</span><b>{number.format(x.kwh)} kWh</b></article>
<article><span>Demanda máxima</span><b>{number.format(x.demand)} kW</b></article><article className={x.excess>0?"alert":""}><span>Exceso de potencia</span><b>{number.format(x.excess)} kW</b></article>
<article><span>Factor de potencia</span><b>{x.pf?x.pf.toFixed(3):"No detectado"}</b></article></div>
<section className="detail-section"><h3>Identificación</h3><dl><div><dt>ID seguimiento</dt><dd>{m?.tracking_code||"S/D"}</dd></div><div><dt>Medidor</dt><dd>{m?.meter_number||"S/D"}</dd></div><div><dt>Suministro / contrato</dt><dd>{m?.supply_number||"S/D"} / {m?.contract_number||"S/D"}</dd></div><div><dt>Código de servicio</dt><dd>{m?.service_code||"S/D"}</dd></div><div><dt>Nomenclatura catastral</dt><dd>{m?.cadastral_number||"S/D"}</dd></div><div><dt>Tensión / tarifa</dt><dd>{invoice.voltage_level||m?.voltage_level||"S/D"} · {invoice.current_tariff_code||"S/D"}</dd></div></dl></section><section className="detail-section"><h3>Factura seleccionada</h3><dl><div><dt>Mes facturado</dt><dd>{(invoice.billing_period||invoice.period_start).slice(0,7)}</dd></div><div><dt>Número de factura</dt><dd>{invoice.invoice_number||"S/D"}</dd></div><div><dt>Potencia contratada</dt><dd>{number.format(x.contracted)} kW</dd></div><div><dt>Importe</dt><dd>{money.format(Number(invoice.total_amount||0))}</dd></div><div><dt>Vencimiento</dt><dd>{invoice.due_date||"S/D"}</dd></div><div><dt>Deuda anterior</dt><dd>{money.format(Number(invoice.previous_debt_amount||0))}</dd></div></dl></section><section className="detail-section"><h3>Historial mensual</h3><div className="mini-history">{sorted.map(h=>{const z=metrics(h);return <button key={h.id}><span>{(h.billing_period||h.period_start).slice(0,7)}</span><b>{number.format(z.kwh)} kWh</b><em>{number.format(z.demand)} kW</em><strong>{money.format(Number(h.total_amount||0))}</strong></button>})}</div></section></aside>
</div>}







































