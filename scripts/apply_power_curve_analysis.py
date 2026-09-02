from pathlib import Path

path = Path("front/app/invoice-analysis-panel.tsx")
text = path.read_text(encoding="utf-8-sig")

old = 'import type { EpenOptimizationMeter } from "./epen-optimization-panel";\n'
new = old + 'import styles from "./power-curve.module.css";\n'
if new not in text:
    if old not in text:
        raise SystemExit("No se encontró el import esperado")
    text = text.replace(old, new, 1)

marker = '''function fmt(metric:Metric,value:number){
  if(metric==="amount")return money.format(value);
  if(metric==="demand")return `${nf.format(value)} kW`;
  if(metric==="pf")return value?value.toFixed(3):"S/D";
  return `${nf.format(value)} kWh`;
}
'''
helpers = marker + '''
const powerMonthNames=["Enero","Febrero","Marzo","Abril","Mayo","Junio","Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"];
function powerRate(i:Invoice){
  return Math.max(0,...(i.invoice_lines||[])
    .filter(x=>["DEM","DEP"].includes(String(x.concept_code||"").toUpperCase()))
    .map(x=>Number(x.unit_price||0)));
}
function buildPowerCurve(history:Invoice[]){
  const valid=history
    .filter(i=>values(i).demand>0)
    .sort((a,b)=>periodOf(a).localeCompare(periodOf(b)));
  const latestContract=[...valid].reverse().find(i=>contractedBands(i).peak>0);
  const latestRateInvoice=[...valid].reverse().find(i=>powerRate(i)>0);
  const currentKw=Number(latestContract?contractedBands(latestContract).peak:0);
  const rate=Number(latestRateInvoice?powerRate(latestRateInvoice):0);
  const rows=powerMonthNames.map((month,idx)=>{
    const monthNumber=idx+1;
    const matches=valid.filter(i=>Number(periodOf(i).slice(5,7))===monthNumber);
    const observations=matches.map(i=>({period:periodOf(i),demand:values(i).demand}));
    const proposalKw=observations.length?Math.max(...observations.map(x=>x.demand)):0;
    const reducibleKw=proposalKw>0?Math.max(0,currentKw-proposalKw):0;
    const savingNet=reducibleKw*rate;
    const saving=savingNet*1.30;
    return{month,monthNumber,observations,proposalKw,reducibleKw,savingNet,saving};
  });
  return{
    currentKw,
    rate,
    rows,
    annualSaving:rows.reduce((sum,row)=>sum+row.saving,0),
    annualSavingNet:rows.reduce((sum,row)=>sum+row.savingNet,0),
    hasData:currentKw>0&&rate>0&&rows.some(row=>row.proposalKw>0)
  };
}
function xmlCell(value:string|number,type:"String"|"Number"="String"){
  const escaped=String(value).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/\"/g,"&quot;");
  return `<Cell><Data ss:Type="${type}">${escaped}</Data></Cell>`;
}
'''
if "function buildPowerCurve(history:Invoice[])" not in text:
    if marker not in text:
        raise SystemExit("No se encontró el bloque fmt esperado")
    text = text.replace(marker, helpers, 1)

old_calc = '''  const powerLines=(selected.invoice_lines||[]).filter(x=>x.concept_code==="DEM"||x.concept_code==="DEP");
  const rate=Math.max(0,...powerLines.map(x=>Number(x.unit_price||0)));
  const excess=Math.max(0,v.contracted-v.demand);
  const powerSaving=excess*rate*1.30;
'''
new_calc = '''  const powerLines=(selected.invoice_lines||[]).filter(x=>x.concept_code==="DEM"||x.concept_code==="DEP");
  const selectedRate=Math.max(0,...powerLines.map(x=>Number(x.unit_price||0)));
  const excess=Math.max(0,v.contracted-v.demand);
  const powerCurve=useMemo(()=>buildPowerCurve(history),[history]);
  const selectedMonthNumber=Number(periodOf(selected).slice(5,7));
  const selectedPowerProposal=powerCurve.rows.find(row=>row.monthNumber===selectedMonthNumber);
  const currentPower=powerCurve.currentKw||v.contracted;
  const proposedPower=Number(selectedPowerProposal?.proposalKw||0);
  const rate=powerCurve.rate||selectedRate;
  const powerSaving=Number(selectedPowerProposal?.saving||0);
  const annualPowerSaving=powerCurve.annualSaving;
'''
if new_calc not in text:
    if old_calc not in text:
        raise SystemExit("No se encontró el cálculo de potencia esperado")
    text = text.replace(old_calc, new_calc, 1)

old_total = '''  const totalSaving=powerSaving+reactiveSaving+tariffSaving;
  const m=selected.meters||invoice.meters;
'''
new_total = '''  const totalSaving=powerSaving+reactiveSaving+tariffSaving;
  const annualTotalSaving=annualPowerSaving+(reactiveSaving*12)+(tariffSaving*12);
  const m=selected.meters||invoice.meters;
'''
if new_total not in text:
    if old_total not in text:
        raise SystemExit("No se encontró el total de ahorro esperado")
    text = text.replace(old_total, new_total, 1)

download_fn = '''  function downloadPowerCurveExcel(){
    if(!powerCurve.hasData)return;
    const header=["Mes","Histórico comparado","Potencia actual (kW)","Propuesta (kW)","Reducción (kW)","Tarifa potencia ($/kW)","Ahorro neto ($)","Ahorro +30% ($)"];
    const rows=powerCurve.rows.map(row=>{
      const historical=row.observations.map(x=>`${x.period.slice(0,4)}: ${nf.format(x.demand)} kW`).join(" | ")||"Sin datos";
      return [row.month,historical,powerCurve.currentKw,row.proposalKw||0,row.reducibleKw,powerCurve.rate,row.savingNet,row.saving];
    });
    const sheetRows=[
      `<Row>${header.map(v=>xmlCell(v)).join("")}</Row>`,
      ...rows.map(row=>`<Row>${row.map((v,index)=>xmlCell(v,index>=2?"Number":"String")).join("")}</Row>`),
      `<Row>${xmlCell("TOTAL ANUAL")}${xmlCell("")}${xmlCell("")}${xmlCell("")}${xmlCell("")}${xmlCell("")}${xmlCell(powerCurve.annualSavingNet,"Number")}${xmlCell(powerCurve.annualSaving,"Number")}</Row>`
    ].join("");
    const xml=`<?xml version="1.0"?><?mso-application progid="Excel.Sheet"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="Curva potencia"><Table>${sheetRows}</Table></Worksheet></Workbook>`;
    const blob=new Blob(["\\ufeff",xml],{type:"application/vnd.ms-excel;charset=utf-8"});
    const url=URL.createObjectURL(blob);
    const link=document.createElement("a");
    const code=(m?.tracking_code||m?.meter_number||"suministro").replace(/[^A-Za-z0-9_-]+/g,"_");
    link.href=url;
    link.download=`Propuesta_Potencia_${code}.xls`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }
'''
if "function downloadPowerCurveExcel()" not in text:
    save_marker = "  async function saveMeterName(){\n"
    if save_marker not in text:
        raise SystemExit("No se encontró saveMeterName")
    text = text.replace(save_marker, download_fn + save_marker, 1)

top_marker = '      </div>\n\n      <div className="invoice-analysis-kpis">\n'
top_block = '''      </div>

      {powerCurve.hasData&&<div className={styles.powerCurveSummary}>
        <div className={styles.powerMetric}>
          <span>Potencia actual</span>
          <b>{nf.format(currentPower)} kW</b>
          <small>última contratación vigente</small>
        </div>
        <div className={styles.powerMetric}>
          <span>Propuesta · {powerMonthNames[selectedMonthNumber-1]}</span>
          <b>{proposedPower>0?`${nf.format(proposedPower)} kW`:"S/D"}</b>
          <small>máximo del mismo mes entre años</small>
        </div>
        <div className={`${styles.powerMetric} ${styles.savingMetric}`}>
          <span>Ahorro</span>
          <b>{money.format(powerSaving)}</b>
          <small>{money.format(annualPowerSaving)} anual según curva</small>
        </div>
        <button type="button" className={styles.excelButton} onClick={downloadPowerCurveExcel}>
          <span>↓</span> Descargar Excel
        </button>
      </div>}

      <div className="invoice-analysis-kpis">
'''
if "className={styles.powerCurveSummary}" not in text:
    if top_marker not in text:
        raise SystemExit("No se encontró el punto de inserción superior")
    text = text.replace(top_marker, top_block, 1)

text = text.replace(
    '<small>{money.format(totalSaving*12)} anualizado</small>',
    '<small>{money.format(annualTotalSaving)} anual según curva</small>',
    1,
)

old_power_row = '''            <div><span>Potencia contratada</span><b>{money.format(powerSaving)}</b><small>{excess>0?`${nf.format(excess)} kW sobrantes × tarifa de potencia + IVA 30%`:"Sin ahorro detectado"}</small></div>'''
new_power_row = '''            <div><span>Potencia contratada</span><b>{money.format(powerSaving)}</b><small>{proposedPower>0&&currentPower>proposedPower?`${nf.format(currentPower-proposedPower)} kW reducibles · curva mensual histórica + 30%`:"Sin ahorro detectado para este mes"}</small></div>'''
if old_power_row in text:
    text = text.replace(old_power_row, new_power_row, 1)
elif new_power_row not in text:
    raise SystemExit("No se encontró la fila de ahorro de potencia")

text = text.replace(
    '<div className="total"><span>Total mensual</span><b>{money.format(totalSaving)}</b><small>{money.format(totalSaving*12)} / año</small></div>',
    '<div className="total"><span>Total mensual</span><b>{money.format(totalSaving)}</b><small>{money.format(annualTotalSaving)} / año según curva</small></div>',
    1,
)

path.write_text(text, encoding="utf-8")

Path("front/app/power-curve.module.css").write_text('''
.powerCurveSummary{
  display:grid;
  grid-template-columns:repeat(3,minmax(150px,1fr)) auto;
  gap:1px;
  align-items:stretch;
  margin:14px 0 18px;
  background:#d8e4df;
  border:1px solid #d8e4df;
  border-radius:14px;
  overflow:hidden;
  box-shadow:0 8px 24px rgba(18,74,58,.06);
}
.powerMetric{min-height:82px;padding:13px 16px;background:#fff;display:flex;flex-direction:column;justify-content:center;}
.powerMetric span{color:#5e746d;font-size:11px;font-weight:800;letter-spacing:.04em;text-transform:uppercase;}
.powerMetric b{margin-top:3px;color:#163f34;font-size:22px;line-height:1.15;}
.powerMetric small{margin-top:4px;color:#71837d;font-size:11px;}
.savingMetric b{color:#087a55;}
.excelButton{min-width:154px;border:0;background:#eaf4ef;color:#14513f;font-weight:800;font-size:13px;padding:0 18px;cursor:pointer;display:flex;gap:7px;align-items:center;justify-content:center;transition:background .15s ease,transform .15s ease;}
.excelButton:hover{background:#dfeee7;}
.excelButton:active{transform:translateY(1px);}
.excelButton span{font-size:17px;}
@media(max-width:900px){.powerCurveSummary{grid-template-columns:1fr 1fr}.excelButton{min-height:58px}}
@media(max-width:600px){.powerCurveSummary{grid-template-columns:1fr}.powerMetric{min-height:72px}.excelButton{min-height:54px}}
'''.lstrip(), encoding="utf-8")
