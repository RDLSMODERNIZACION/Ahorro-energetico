import { consumptionPeriod, type PowerInvoice } from './power-history';
export type PowerStrategy = 'annual' | 'quarterly' | 'conservative';
export type T2Invoice = PowerInvoice & { contracted_kw_peak?: number; current_tariff_code?: string; net_taxable?: number; subtotal?: number; vat_amount?: number; vat_perception_amount?: number; meters?: { current_tariff_code?: string }; invoice_lines?: Array<{concept_code?: string; unit_price?: number}> };
export const quarters = [{label:'Noviembre–Enero',months:[11,12,1]},{label:'Febrero–Abril',months:[2,3,4]},{label:'Mayo–Julio',months:[5,6,7]},{label:'Agosto–Octubre',months:[8,9,10]}];
const names = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
const finite = (v: unknown): v is number => v !== null && v !== undefined && Number.isFinite(Number(v));
export function billingDemand(i:T2Invoice):number|null {
  const rows=i.invoice_measurements || [];
  const registered=rows.map(m=>m.registered_demand_peak_kw).filter(finite).map(Number);
  if(registered.length)return Math.max(...registered);
  const precise=rows.map(m=>m.demand_kw).filter(finite).map(Number);
  return precise.length?Math.max(...precise):null;
}
export function powerCost(contract:number,demand:number,rate:number){
  const contractedCost=contract*rate, excessKw=Math.max(0,demand-contract), excessCost=excessKw*rate*1.5;
  return {contractedCost,excessKw,excessCost,total:contractedCost+excessCost};
}
function bestPower(demands:number[],rate:number){
  // Piecewise linear objective: a minimum is at a demand breakpoint or the tariff minimum.
  const candidates=[10,...demands.filter(d=>d>=10&&d<50)];
  return candidates.sort((a,b)=>b-a).reduce((best,p)=>{
    const cost=demands.reduce((s,d)=>s+powerCost(p,d,rate).total,0);
    return cost < best.cost-0.005?{kw:p,cost}:best;
  },{kw:10,cost:Infinity}).kw;
}
export function buildT2Comparison(history:T2Invoice[]){
  const sorted=[...history].sort((a,b)=>String(b.billing_period||b.period_start).localeCompare(String(a.billing_period||a.period_start)));
  const latest=sorted[0];
  if(!String(latest?.current_tariff_code||latest?.meters?.current_tariff_code||'').toUpperCase().startsWith('T2'))return null;
  const currentKw=Number(latest?.contracted_kw_peak||0);
  const rateInvoice=sorted.find(i=>i.invoice_lines?.some(l=>['DEM','DEP'].includes(l.concept_code||'')&&Number(l.unit_price)>0));
  const rate=Math.max(0,...(rateInvoice?.invoice_lines||[]).filter(l=>['DEM','DEP'].includes(l.concept_code||'')).map(l=>Number(l.unit_price||0)));
  const net=Number(rateInvoice?.net_taxable||rateInvoice?.subtotal||0);
  const hasTaxes=net>0&&finite(rateInvoice?.vat_amount)&&finite(rateInvoice?.vat_perception_amount);
  const taxMultiplier=hasTaxes?1+(Number(rateInvoice?.vat_amount)+Number(rateInvoice?.vat_perception_amount))/net:1;
  const monthly=names.map((month,index)=>{
    const periods=new Map<string,{period:string; demand:number;billingPeriod:string}>();
    for(const i of history){const p=consumptionPeriod(i),d=billingDemand(i);if(Number(p.slice(5,7))!==index+1||d===null)continue;
      if(!periods.has(p)||periods.get(p)!.demand<d)periods.set(p,{period:p,demand:d,billingPeriod:String(i.billing_period||'').slice(0,7)});
    }
    const observations=[...periods.values()].sort((a,b)=>b.period.localeCompare(a.period)).slice(0,2);
    return {month,monthNumber:index+1,observations,demand:observations.length?Math.max(...observations.map(o=>o.demand)):null};
  });
  const missing=monthly.filter(r=>r.demand===null).map(r=>r.month);
  const outOfRange=monthly.some(r=>Number(r.demand)>=50);
  const complete=missing.length===0&&rate>0&&currentKw>=10&&!outOfRange;
  const demands=monthly.map(r=>r.demand||0);
  const annual=complete?bestPower(demands,rate):0;
  const scenarios=(['annual','quarterly','conservative'] as PowerStrategy[]).map(id=>{
    const rows=monthly.map(r=>{
      const quarter=quarters.find(q=>q.months.includes(r.monthNumber))!;
      const ds=quarter.months.map(m=>monthly[m-1].demand||0);
      const proposalKw=complete?(id==='annual'?annual:id==='quarterly'?bestPower(ds,rate):Math.max(10,...ds)):0;
      const baseline=powerCost(currentKw,r.demand||0,rate),cost=powerCost(proposalKw,r.demand||0,rate);
      const savingNet=complete?baseline.total-cost.total:0;
      return {...r,proposalKw,quarter:quarter.label,method:id==='annual'?'anual':'trimestral',quarterlyProposalKw:Math.max(10,...ds),monthlyProposalKw:Math.max(10,r.demand||0),spreadKw:Math.max(...ds)-Math.min(...ds),extraCost:0,reason:'Costo de contratación + excesos T2 a 1,5 × precio',reducibleKw:currentKw-proposalKw,savingNet,saving:savingNet*taxMultiplier,...cost,baselineCost:baseline.total};
    });
    return {id,label:id==='annual'?'Fija anual optimizada':id==='quarterly'?'Trimestral optimizada':'Trimestral sin excesos previstos',rows,annualCost:complete?rows.reduce((s,r)=>s+r.total,0):0,contractedCost:complete?rows.reduce((s,r)=>s+r.contractedCost,0):0,excessCost:complete?rows.reduce((s,r)=>s+r.excessCost,0):0,excessMonths:complete?rows.filter(r=>r.excessKw>0).length:0,annualSavingNet:rows.reduce((s,r)=>s+r.savingNet,0),annualSaving:rows.reduce((s,r)=>s+r.saving,0)};
  });
  const decline=monthly.filter(r=>r.observations.length===2&&r.observations[0].demand<r.observations[1].demand*0.7).map(r=>r.month);
  return {currentKw,rate,ratePeriod:String(rateInvoice?.billing_period||'').slice(0,7),minimumKw:10,tariffCode:'T2',complete,missing,outOfRange,decline,taxMultiplier,hasTaxes,monthly,scenarios};
}
export type T2Comparison=NonNullable<ReturnType<typeof buildT2Comparison>>;
