"use client";

import { supabase } from "./lib/supabase";

const API="https://ahorro-energetico.onrender.com";
const money=new Intl.NumberFormat("es-AR",{style:"currency",currency:"ARS",maximumFractionDigits:0});
const nf=new Intl.NumberFormat("es-AR",{maximumFractionDigits:0});
const monthNames=["Enero","Febrero","Marzo","Abril","Mayo","Junio","Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"];

type Measurement={demand_kw?:number;registered_demand_peak_kw?:number;meter_number?:string};
type Line={concept_code?:string;quantity?:number;unit_price?:number};
type Meter={meter_number?:string;tracking_code?:string;contracted_kw_peak?:number};
type Invoice={id:string;billing_period?:string;period_start?:string;issue_date?:string;contracted_kw_peak?:number;meters?:Meter;invoice_measurements?:Measurement[];invoice_lines?:Line[]};
type Organization={organization_id:string};

type CurveRow={
  month:string;
  monthNumber:number;
  observations:{period:string;demand:number}[];
  proposalKw:number;
  reducibleKw:number;
  savingNet:number;
  saving:number;
};
type Curve={currentKw:number;rate:number;rows:CurveRow[];annualSaving:number;annualSavingNet:number};

let invoicePromise:Promise<Invoice[]>|null=null;
let scheduled:number|undefined;

function periodOf(i:Invoice){return String(i.billing_period||i.period_start||"").slice(0,7)}
function demandOf(i:Invoice){return Math.max(0,...(i.invoice_measurements||[]).map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)))}
function contractedOf(i:Invoice){
  const line=Math.max(0,...(i.invoice_lines||[]).filter(x=>["DEP","DEM"].includes(String(x.concept_code||"").toUpperCase())).map(x=>Number(x.quantity||0)));
  return Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||line||0);
}
function rateOf(i:Invoice){return Math.max(0,...(i.invoice_lines||[]).filter(x=>["DEP","DEM"].includes(String(x.concept_code||"").toUpperCase())).map(x=>Number(x.unit_price||0)))}
function meterOf(i:Invoice){return String(i.meters?.meter_number||(i.invoice_measurements||[]).find(x=>x.meter_number)?.meter_number||"")}

async function loadInvoices(){
  if(invoicePromise)return invoicePromise;
  invoicePromise=(async()=>{
    const{data}=await supabase.auth.getSession();
    if(!data.session)throw new Error("Sesión vencida");
    const auth={Authorization:`Bearer ${data.session.access_token}`};
    const orgResponse=await fetch(`${API}/api/organizations`,{cache:"no-store",headers:auth});
    if(!orgResponse.ok)throw new Error(await orgResponse.text());
    const orgs=await orgResponse.json() as Organization[];
    const orgId=orgs[0]?.organization_id;
    if(!orgId)throw new Error("Organización no disponible");
    const response=await fetch(`${API}/api/organizations/${orgId}/invoices?limit=5000`,{cache:"no-store",headers:auth});
    if(!response.ok)throw new Error(await response.text());
    return await response.json() as Invoice[];
  })().catch(error=>{invoicePromise=null;throw error});
  return invoicePromise;
}

function buildCurve(history:Invoice[]):Curve|null{
  const valid=history.filter(i=>periodOf(i)&&demandOf(i)>0).sort((a,b)=>periodOf(a).localeCompare(periodOf(b)));
  if(!valid.length)return null;
  const latestContract=[...valid].reverse().find(i=>contractedOf(i)>0);
  const latestRate=[...valid].reverse().find(i=>rateOf(i)>0);
  const currentKw=latestContract?contractedOf(latestContract):0;
  const rate=latestRate?rateOf(latestRate):0;
  if(!(currentKw>0)||!(rate>0))return null;
  const rows=monthNames.map((month,idx)=>{
    const monthNumber=idx+1;
    const observations=valid.filter(i=>Number(periodOf(i).slice(5,7))===monthNumber).map(i=>({period:periodOf(i),demand:demandOf(i)}));
    const proposalKw=observations.length?Math.max(...observations.map(x=>x.demand)):0;
    const reducibleKw=proposalKw>0?Math.max(0,currentKw-proposalKw):0;
    const savingNet=reducibleKw*rate;
    return{month,monthNumber,observations,proposalKw,reducibleKw,savingNet,saving:savingNet*1.30};
  });
  return{
    currentKw,
    rate,
    rows,
    annualSaving:rows.reduce((sum,row)=>sum+row.saving,0),
    annualSavingNet:rows.reduce((sum,row)=>sum+row.savingNet,0)
  };
}

function parseMoney(text:string|undefined){
  if(!text)return 0;
  const clean=text.replace(/[^0-9,-]/g,"").replace(/\./g,"").replace(",",".");
  return Number(clean||0)||0;
}
function escapeXml(value:string|number){return String(value).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;")}
function cell(value:string|number,type:"String"|"Number"="String"){return `<Cell><Data ss:Type="${type}">${escapeXml(value)}</Data></Cell>`}
function setText(node:Element|null,value:string){if(node&&node.textContent!==value)node.textContent=value}

function downloadExcel(curve:Curve,meterNumber:string,tracking:string){
  const header=["Mes","Histórico comparado","Potencia actual (kW)","Propuesta (kW)","Reducción (kW)","Tarifa potencia ($/kW)","Ahorro neto ($)","Ahorro +30% ($)"];
  const rows=curve.rows.map(row=>[
    row.month,
    row.observations.map(x=>`${x.period.slice(0,4)}: ${nf.format(x.demand)} kW`).join(" | ")||"Sin datos",
    curve.currentKw,row.proposalKw,row.reducibleKw,curve.rate,row.savingNet,row.saving
  ]);
  const sheet=[
    `<Row>${header.map(v=>cell(v)).join("")}</Row>`,
    ...rows.map(row=>`<Row>${row.map((v,index)=>cell(v,index>=2?"Number":"String")).join("")}</Row>`),
    `<Row>${cell("TOTAL ANUAL")}${cell("")}${cell("")}${cell("")}${cell("")}${cell("")}${cell(curve.annualSavingNet,"Number")}${cell(curve.annualSaving,"Number")}</Row>`
  ].join("");
  const xml=`<?xml version="1.0"?><?mso-application progid="Excel.Sheet"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="Curva potencia"><Table>${sheet}</Table></Worksheet></Workbook>`;
  const blob=new Blob(["\ufeff",xml],{type:"application/vnd.ms-excel;charset=utf-8"});
  const url=URL.createObjectURL(blob);
  const link=document.createElement("a");
  const code=(tracking||meterNumber||"suministro").replace(/[^A-Za-z0-9_-]+/g,"_");
  link.href=url;
  link.download=`Propuesta_Potencia_${code}.xls`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function ensureStyle(){
  if(document.getElementById("power-curve-enhancer-style"))return;
  const style=document.createElement("style");
  style.id="power-curve-enhancer-style";
  style.textContent=`
    .power-curve-summary{display:grid;grid-template-columns:repeat(3,minmax(150px,1fr)) auto;gap:1px;align-items:stretch;margin:14px 0 18px;background:#d8e4df;border:1px solid #d8e4df;border-radius:14px;overflow:hidden;box-shadow:0 8px 24px rgba(18,74,58,.06)}
    .power-curve-metric{min-height:82px;padding:13px 16px;background:#fff;display:flex;flex-direction:column;justify-content:center}
    .power-curve-metric span{color:#5e746d;font-size:11px;font-weight:800;letter-spacing:.04em;text-transform:uppercase}
    .power-curve-metric b{margin-top:3px;color:#163f34;font-size:22px;line-height:1.15}
    .power-curve-metric small{margin-top:4px;color:#71837d;font-size:11px}.power-curve-saving b{color:#087a55}
    .power-curve-excel{min-width:154px;border:0;background:#eaf4ef;color:#14513f;font-weight:800;font-size:13px;padding:0 18px;cursor:pointer;display:flex;gap:7px;align-items:center;justify-content:center}.power-curve-excel:hover{background:#dfeee7}
    @media(max-width:900px){.power-curve-summary{grid-template-columns:1fr 1fr}.power-curve-excel{min-height:58px}}
    @media(max-width:600px){.power-curve-summary{grid-template-columns:1fr}.power-curve-metric{min-height:72px}.power-curve-excel{min-height:54px}}
  `;
  document.head.appendChild(style);
}

function updateExistingSavings(powerSaving:number,annualPowerSaving:number,currentKw:number,proposalKw:number){
  const rows=[...document.querySelectorAll<HTMLElement>(".invoice-analysis-saving-list > div")];
  const powerRow=rows.find(row=>row.querySelector("span")?.textContent?.trim()==="Potencia contratada");
  if(powerRow){
    setText(powerRow.querySelector("b"),money.format(powerSaving));
    setText(powerRow.querySelector("small"),currentKw>proposalKw?`${nf.format(currentKw-proposalKw)} kW reducibles · curva mensual histórica + 30%`:"Sin ahorro detectado para este mes");
  }
  const reactiveRow=rows.find(row=>row.querySelector("span")?.textContent?.trim()==="Factor de potencia");
  const tariffRow=rows.find(row=>row.querySelector("span")?.textContent?.trim()==="Encuadramiento tarifario");
  const reactive=parseMoney(reactiveRow?.querySelector("b")?.textContent||"");
  const tariff=parseMoney(tariffRow?.querySelector("b")?.textContent||"");
  const monthly=powerSaving+reactive+tariff;
  const annual=annualPowerSaving+reactive*12+tariff*12;
  const totalRow=rows.find(row=>row.querySelector("span")?.textContent?.trim()==="Total mensual");
  if(totalRow){
    setText(totalRow.querySelector("b"),money.format(monthly));
    setText(totalRow.querySelector("small"),`${money.format(annual)} / año según curva`);
  }
  const kpis=[...document.querySelectorAll<HTMLElement>(".invoice-analysis-kpis article")];
  const savingKpi=kpis.find(row=>row.querySelector("span")?.textContent?.trim()==="Ahorro potencial");
  if(savingKpi){
    setText(savingKpi.querySelector("b"),money.format(monthly));
    setText(savingKpi.querySelector("small"),`${money.format(annual)} anual según curva`);
  }
}

async function enhance(){
  const page=document.querySelector<HTMLElement>(".invoice-analysis-page");
  if(!page)return;
  const top=page.querySelector<HTMLElement>(".invoice-analysis-top");
  if(!top)return;
  const identity=top.querySelector("p")?.textContent||"";
  const meterNumber=identity.match(/Medidor\s+([^·\s]+)/i)?.[1]?.trim()||"";
  const tracking=identity.split("·")[0]?.trim()||"";
  if(!meterNumber)return;
  const selectedPeriod=page.querySelector<HTMLElement>(".invoice-analysis-period b")?.textContent?.trim()||"";
  const monthNumber=Number(selectedPeriod.slice(5,7));
  if(!(monthNumber>=1&&monthNumber<=12))return;
  try{
    const invoices=await loadInvoices();
    const history=invoices.filter(i=>meterOf(i)===meterNumber);
    const curve=buildCurve(history);
    if(!curve)return;
    const row=curve.rows.find(x=>x.monthNumber===monthNumber);
    if(!row||!(row.proposalKw>0))return;
    ensureStyle();
    let box=page.querySelector<HTMLElement>("#power-curve-summary-dom");
    if(!box){
      box=document.createElement("div");
      box.id="power-curve-summary-dom";
      box.className="power-curve-summary";
      top.insertAdjacentElement("afterend",box);
    }
    const signature=`${meterNumber}|${selectedPeriod}|${curve.currentKw}|${curve.rate}|${row.proposalKw}|${row.saving}|${curve.annualSaving}`;
    if(box.dataset.signature!==signature){
      box.dataset.signature=signature;
      box.innerHTML=`
        <div class="power-curve-metric"><span>Potencia actual</span><b>${nf.format(curve.currentKw)} kW</b><small>última contratación vigente</small></div>
        <div class="power-curve-metric"><span>Propuesta · ${row.month}</span><b>${nf.format(row.proposalKw)} kW</b><small>máximo del mismo mes entre años</small></div>
        <div class="power-curve-metric power-curve-saving"><span>Ahorro</span><b>${money.format(row.saving)}</b><small>${money.format(curve.annualSaving)} anual según curva</small></div>
        <button type="button" class="power-curve-excel"><span>↓</span> Descargar Excel</button>`;
      box.querySelector("button")?.addEventListener("click",()=>downloadExcel(curve,meterNumber,tracking));
    }
    updateExistingSavings(row.saving,curve.annualSaving,curve.currentKw,row.proposalKw);
  }catch(error){
    console.warn("No se pudo calcular la curva mensual de potencia",error);
  }
}

function scheduleEnhance(){
  if(typeof window==="undefined")return;
  if(scheduled)window.clearTimeout(scheduled);
  scheduled=window.setTimeout(()=>{void enhance()},60);
}

if(typeof window!=="undefined"){
  scheduleEnhance();
  const observer=new MutationObserver(scheduleEnhance);
  observer.observe(document.documentElement,{childList:true,subtree:true,characterData:true});
}
