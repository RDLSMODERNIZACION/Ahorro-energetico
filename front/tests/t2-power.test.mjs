import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import {readFileSync} from 'node:fs';
const compile=path=>ts.transpileModule(readFileSync(new URL(path,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const url=js=>`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`;
const historyUrl=url(compile('../app/lib/power-history.ts'));
const {buildT2Comparison,powerCost,billingDemand}=await import(url(compile('../app/lib/t2-power.ts').replace("'./power-history'",JSON.stringify(historyUrl))));
const demands=[17,14,17,25,25,27,27,25,24,20,13,13];
function fixture(ds=demands){return ds.map((d,idx)=>({billing_period:`2025-${String(idx+1).padStart(2,'0')}-01`,current_tariff_code:'T2',contracted_kw_peak:25,invoice_measurements:[{registered_demand_peak_kw:d}],invoice_lines:[{concept_code:'DEM',unit_price:49800.44}]}));}
test('reproduces supply 00081281 annual and quarterly comparison including baseline penalties',()=>{
 const m=buildT2Comparison(fixture());assert.equal(m.complete,true);
 const [annual,quarterly,conservative]=m.scenarios;
 assert.equal(annual.rows[0].proposalKw,17);
 assert.ok(Math.abs(annual.annualCost-14193125.4)<0.01);
 assert.ok(Math.abs(quarterly.annualCost-13072615.5)<0.01);
 assert.ok(Math.abs(conservative.annualCost-14043724.08)<0.01);
 assert.ok(Math.abs(quarterly.annualSavingNet-2166319.14)<0.01);
 assert.equal(conservative.excessMonths,0);assert.equal(quarterly.excessMonths,3);
 assert.deepEqual([10,1,4,7].map(i=>quarterly.rows[i].proposalKw),[13,17,27,24]);
 assert.ok(annual.rows.some(r=>r.savingNet<0));
});
test('optimizer matches brute force and always includes excess charge only on the excess',()=>{
 assert.equal(powerCost(20,25,100).total,2750);
 for(const ds of [demands,[0,0,10,11,12,13,14,15,16,17,18,19],[49,12,14,11,20,32,23,19,11,17,18,25]]){
  const m=buildT2Comparison(fixture(ds));const brute=Math.min(...Array.from({length:40},(_,i)=>ds.reduce((s,d)=>s+powerCost(10+i,d,m.rate).total,0)));
  assert.ok(Math.abs(m.scenarios[0].annualCost-brute)<0.01);
 }
});
test('null is missing, zero is a real measurement, missing months prevent annual savings',()=>{
 assert.equal(billingDemand({invoice_measurements:[]}),null);
 assert.equal(billingDemand({invoice_measurements:[{registered_demand_peak_kw:0,demand_kw:0}]}),0);
 const h=fixture();h[2].invoice_measurements=[];const m=buildT2Comparison(h);
 assert.equal(m.complete,false);assert.deepEqual(m.missing,['Marzo']);assert.equal(m.scenarios[0].annualSaving,0);
});
test('uses latest price rather than highest historical price; taxes never default to 30 percent',()=>{
 const h=fixture();h[0].invoice_lines[0].unit_price=100000;let m=buildT2Comparison(h);
 assert.equal(m.rate,49800.44);assert.equal(m.hasTaxes,false);assert.equal(m.taxMultiplier,1);
 Object.assign(h[11],{net_taxable:100,vat_amount:27,vat_perception_amount:3});m=buildT2Comparison(h);assert.equal(m.taxMultiplier,1.3);
});
test('does not apply T2 formula to T3 or demand >= 50; uses billed demand and warns on decline',()=>{
 const h=fixture();h[11].current_tariff_code='T3';assert.equal(buildT2Comparison(h),null);
 h[11].current_tariff_code='T2';h[1].invoice_measurements[0].registered_demand_peak_kw=50;assert.equal(buildT2Comparison(h).complete,false);
 assert.equal(billingDemand({invoice_measurements:[{registered_demand_peak_kw:25,demand_kw:25.39}]}),25);
 const newer={...fixture()[0],billing_period:'2026-01-01',invoice_measurements:[{registered_demand_peak_kw:8}]};
 assert.deepEqual(buildT2Comparison([...fixture(),newer]).decline,['Enero']);
});
