from pathlib import Path

path=Path('front/app/page.tsx')
text=path.read_text(encoding='utf-8-sig')

marker='''function renderAiRichText(text:string,onOpenReference?:(reference:string)=>void){\n'''
helpers='''function dashboardPowerDemand(i:Invoice){\n  return Math.max(0,...(i.invoice_measurements||[]).map(m=>Number(m.demand_kw||m.registered_demand_peak_kw||0)));\n}\nfunction dashboardPowerContract(i:Invoice){\n  const line=Math.max(0,...(i.invoice_lines||[]).filter(x=>["DEP","DEM"].includes(String(x.concept_code||"").toUpperCase())).map(x=>Number(x.quantity||0)));\n  return Number(i.contracted_kw_peak||i.meters?.contracted_kw_peak||line||0);\n}\nfunction dashboardPowerRate(i:Invoice){\n  return Math.max(0,...(i.invoice_lines||[]).filter(x=>["DEP","DEM"].includes(String(x.concept_code||"").toUpperCase())).map(x=>Number(x.unit_price||0)));\n}\nfunction buildDashboardPowerCurve(invoices:Invoice[],period:string){\n  const monthNumber=Number(String(period||"").slice(5,7));\n  const meterIds=[...new Set(invoices.map(i=>i.meter_id))];\n  const meters=meterIds.map(meterId=>{\n    const history=invoices.filter(i=>i.meter_id===meterId&&dashboardPowerDemand(i)>0).sort((a,b)=>String(a.billing_period||a.period_start).localeCompare(String(b.billing_period||b.period_start)));\n    const latestContract=[...history].reverse().find(i=>dashboardPowerContract(i)>0);\n    const latestRate=[...history].reverse().find(i=>dashboardPowerRate(i)>0);\n    const currentKw=latestContract?dashboardPowerContract(latestContract):0;\n    const rate=latestRate?dashboardPowerRate(latestRate):0;\n    const rows=Array.from({length:12},(_,idx)=>{\n      const target=idx+1;\n      const demands=history.filter(i=>Number(String(i.billing_period||i.period_start).slice(5,7))===target).map(dashboardPowerDemand);\n      const proposalKw=demands.length?Math.max(...demands):0;\n      const reducibleKw=proposalKw>0?Math.max(0,currentKw-proposalKw):0;\n      return{monthNumber:target,proposalKw,saving:reducibleKw*rate*1.30};\n    });\n    const selected=rows.find(r=>r.monthNumber===monthNumber);\n    return{meterId,currentKw,rate,rows,monthlySaving:Number(selected?.saving||0),annualSaving:rows.reduce((s,r)=>s+r.saving,0)};\n  }).filter(x=>x.currentKw>0&&x.rate>0);\n  return{\n    meters,\n    monthlySaving:meters.reduce((s,x)=>s+x.monthlySaving,0),\n    annualSaving:meters.reduce((s,x)=>s+x.annualSaving,0),\n    opportunityMeterIds:new Set(meters.filter(x=>x.monthlySaving>0).map(x=>x.meterId))\n  };\n}\n\n'''+marker
if 'function buildDashboardPowerCurve(invoices:Invoice[],period:string)' not in text:
    if marker not in text: raise SystemExit('No se encontró renderAiRichText')
    text=text.replace(marker,helpers,1)

old='''  const dashboardPowerMonthly=dashboardInvoices.reduce((sum,i)=>sum+invoicePowerSaving(i).amount,0);\n  const dashboardReactiveMonthly=dashboardInvoices.reduce((sum,i)=>sum+invoiceReactiveSaving(i),0);\n'''
new='''  const dashboardPowerCurve=buildDashboardPowerCurve(invoices,dashboardPeriod);\n  const dashboardPowerMonthly=dashboardPowerCurve.monthlySaving;\n  const dashboardPowerAnnual=dashboardPowerCurve.annualSaving;\n  const dashboardReactiveMonthly=dashboardInvoices.reduce((sum,i)=>sum+invoiceReactiveSaving(i),0);\n'''
if new not in text:
    if old not in text: raise SystemExit('No se encontró dashboardPowerMonthly')
    text=text.replace(old,new,1)

old='''  const dashboardTotalMonthly=dashboardPowerMonthly+dashboardReactiveMonthly+dashboardRateMonthly;\n'''
new='''  const dashboardTotalMonthly=dashboardPowerMonthly+dashboardReactiveMonthly+dashboardRateMonthly;\n  const dashboardTotalAnnual=dashboardPowerAnnual+(dashboardReactiveMonthly*12)+(dashboardRateMonthly*12);\n'''
if new not in text:
    if old not in text: raise SystemExit('No se encontró dashboardTotalMonthly')
    text=text.replace(old,new,1)

old='''    const hasPower=invoicePowerSaving(i).amount>0;\n'''
new='''    const hasPower=dashboardPowerCurve.opportunityMeterIds.has(i.meter_id);\n'''
if new not in text:
    if old not in text: raise SystemExit('No se encontró hasPower')
    text=text.replace(old,new,1)

old='''  const dashboardPowerExcess=dashboardInvoices.filter(i=>metrics(i).excess>0).length;\n'''
new='''  const dashboardPowerExcess=dashboardPowerCurve.opportunityMeterIds.size;\n'''
if new not in text:
    if old not in text: raise SystemExit('No se encontró dashboardPowerExcess')
    text=text.replace(old,new,1)

text=text.replace('<small>{money.format(dashboardTotalMonthly*12)} anualizado ×12</small>','<small>{money.format(dashboardTotalAnnual)} anual · potencia según curva mensual</small>',1)
text=text.replace('sub={`Valores calculados sobre ${dashboardPeriodLabel}. El anual es una proyección del ahorro mensual × 12, con 30% de IVA.`}','sub={`Potencia: curva mensual histórica por suministro. Factor de potencia y tarifa: proyección mensual × 12. Valores con 30% de IVA donde corresponde.`}',1)
text=text.replace('<strong>{money.format(dashboardPowerMonthly*12)}</strong>','<strong>{money.format(dashboardPowerAnnual)}</strong>',1)
text=text.replace('<p>Contratada menos máxima registrada del período, sin margen.</p>','<p>Curva anual: para cada mes toma la mayor demanda del mismo mes entre los años disponibles, contra la última potencia contratada.</p>',1)
text=text.replace('<strong>{money.format(dashboardTotalMonthly*12)}</strong>\n        <small>{money.format(dashboardTotalMonthly)} mensual · {dashboardPeriodLabel}</small>\n        <p>Proyección anual basada únicamente en el ahorro detectado del mes.</p>','<strong>{money.format(dashboardTotalAnnual)}</strong>\n        <small>{money.format(dashboardTotalMonthly)} mensual · {dashboardPeriodLabel}</small>\n        <p>Potencia anual según curva de 12 meses; los demás ahorros se anualizan desde el período actual.</p>',1)

path.write_text(text,encoding='utf-8')
