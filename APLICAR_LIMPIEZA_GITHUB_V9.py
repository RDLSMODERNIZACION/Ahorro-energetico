
from pathlib import Path
import re, sys, shutil, datetime

repo = Path(sys.argv[1]).resolve()
front = repo / "front/app/invoice-analysis-panel.tsx"
css = repo / "front/app/globals.css"
main = repo / "back/app/main.py"
payload_backend = Path(__file__).resolve().parent / "payload/back/app/routers/tariff_history.py"
backend_target = repo / "back/app/routers/tariff_history.py"

if not front.exists() or not css.exists() or not main.exists():
    raise SystemExit("No encuentro la estructura esperada del repositorio.")

stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = Path(__file__).resolve().parent / f"backup_clean_v9_{stamp}"
backup_dir.mkdir(parents=True, exist_ok=True)
for p in (front, css, main):
    shutil.copy2(p, backup_dir / p.name)

shutil.copy2(payload_backend, backend_target)

m = main.read_text(encoding="utf-8-sig")
if "tariff_history" not in m:
    im = re.search(r"from \.routers import ([^\r\n]+)", m)
    if not im:
        raise SystemExit("No encuentro el import de routers en main.py")
    full = im.group(0)
    m = m.replace(full, full + ",tariff_history", 1)
if 'api.include_router(tariff_history.router,prefix="/api")' not in m:
    anchor = 'api.include_router(epen_optimization.router,prefix="/api")'
    if anchor not in m:
        anchor = 'api.include_router(analysis.router,prefix="/api")'
    if anchor not in m:
        raise SystemExit("No encuentro dónde registrar tariff_history.")
    m = m.replace(anchor, anchor + '\napi.include_router(tariff_history.router,prefix="/api")', 1)
main.write_text(m, encoding="utf-8")

text = front.read_text(encoding="utf-8-sig")

def function_spans(src: str, name: str):
    spans=[]
    needle=f"function {name}("
    pos=0
    while True:
        start=src.find(needle,pos)
        if start<0:
            break
        brace=src.find("{",start)
        if brace<0:
            raise SystemExit(f"No encontré apertura de {name}")
        depth=0
        i=brace
        quote=None
        escape=False
        line_comment=False
        block_comment=False
        while i < len(src):
            c=src[i]
            n=src[i+1] if i+1<len(src) else ""
            if line_comment:
                if c=="\n":
                    line_comment=False
                i+=1
                continue
            if block_comment:
                if c=="*" and n=="/":
                    block_comment=False
                    i+=2
                    continue
                i+=1
                continue
            if quote:
                if escape:
                    escape=False
                elif c=="\\":
                    escape=True
                elif c==quote:
                    quote=None
                i+=1
                continue
            if c=="/" and n=="/":
                line_comment=True
                i+=2
                continue
            if c=="/" and n=="*":
                block_comment=True
                i+=2
                continue
            if c in ("'", '"', "`"):
                quote=c
                i+=1
                continue
            if c=="{":
                depth+=1
            elif c=="}":
                depth-=1
                if depth==0:
                    end=i+1
                    while end < len(src) and src[end] in "\r\n":
                        end+=1
                    spans.append((start,end))
                    pos=end
                    break
            i+=1
        else:
            raise SystemExit(f"No pude cerrar function {name}")
    return spans

# El GitHub actual tiene funciones duplicadas. Sacamos TODAS y ponemos una sola.
spans=function_spans(text,"TariffSavingTrend")
for a,b in reversed(spans):
    text=text[:a]+text[b:]

canonical_trend = '''function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()]
      .sort((a,b)=>a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period,row])=>({period,row,value:Math.max(0,Number(row.monthly_saving||0))}));
  },[rows]);

  if(!data.length||!data.some(d=>d.value>0)){
    return <div className="invoice-tariff-no-data">
      <b>Sin ahorro tarifario valorizado</b>
      <span>No hay una simulación mensual disponible para este medidor.</span>
    </div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  const axis=(value:number)=>{
    if(value>=1000000)return `$ ${(value/1000000).toLocaleString("es-AR",{maximumFractionDigits:1})} M`;
    if(value>=1000)return `$ ${(value/1000).toLocaleString("es-AR",{maximumFractionDigits:0})} mil`;
    return money.format(value);
  };

  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}>
          <line x1={left} x2={width-right} y1={y} y2={y}/>
          <text x={left-10} y={y+4} textAnchor="end">{axis(max*step)}</text>
        </g>
      })}

      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        return <g
          className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {d.row.current_tariff||"Actual"} → {d.row.recommended_tariff||"Propuesta"} · {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>

    <div className="invoice-tariff-legend">
      <span><i/>Ahorro mensual con la tarifa propuesta</span>
    </div>
  </div>
}

'''
insert_at=text.find("function InvoiceTrend(")
if insert_at<0:
    raise SystemExit("No encuentro function InvoiceTrend.")
text=text[:insert_at]+canonical_trend+text[insert_at:]

if text.count("function TariffSavingTrend(")!=1:
    raise SystemExit("No quedó una única TariffSavingTrend.")

title='<h3>Evolución histórica del medidor</h3>'
title_pos=text.find(title)
if title_pos<0:
    raise SystemExit("No encuentro Evolución histórica del medidor.")
section_start=text.rfind('<section className="invoice-analysis-panel">',0,title_pos)
next_grid=text.find('<div className="invoice-analysis-grid">',title_pos)
if section_start<0 or next_grid<0:
    raise SystemExit("No pude aislar la sección histórica.")

section = '''<section className="invoice-analysis-panel">
        <div className="invoice-analysis-chart-head">
          <div>
            <h3>Evolución histórica del medidor</h3>
            <p>Hasta 24 meses. Tocá una barra para abrir esa factura.</p>
          </div>
          <div className="invoice-analysis-metrics">
            <button className={metric==="kwh"?"active":""} onClick={()=>setMetric("kwh")}>Consumo</button>
            <button className={metric==="amount"?"active":""} onClick={()=>setMetric("amount")}>Importe</button>
            <button className={metric==="demand"?"active":""} onClick={()=>setMetric("demand")}>Demanda</button>
            <button className={metric==="pf"?"active":""} onClick={()=>setMetric("pf")}>Factor potencia</button>
            <button className={metric==="tariff"?"active":""} onClick={()=>setMetric("tariff")}>Ahorro tarifario</button>
          </div>
        </div>

        {metric==="tariff" ? (() => {
          const legacyRows=tariffSavings
            .filter(x=>x.meter_id===selected.meter_id)
            .map(x=>({
              billing_period:String(x.billing_period).slice(0,7),
              monthly_saving:Number(x.monthly_saving_with_vat||0),
              current_tariff:x.current_tariff,
              recommended_tariff:x.recommended_tariff
            }));

          const advancedRows=(advancedTariffHistory?.points||[]).map(x=>({
            billing_period:String(x.billing_period).slice(0,7),
            monthly_saving:Number(x.monthly_saving||0),
            current_tariff:x.current_tariff,
            recommended_tariff:x.recommended_tariff
          }));

          const chartRows=advancedRows.some(x=>x.monthly_saving>0) ? advancedRows : legacyRows;

          return <TariffSavingTrend
            rows={chartRows}
            selectedPeriod={periodOf(selected)}
            onPeriod={setSelectedPeriod}
          />;
        })() : (
          <InvoiceTrend
            rows={sorted}
            metric={metric}
            selectedPeriod={periodOf(selected)}
            onPeriod={setSelectedPeriod}
          />
        )}
      </section>
      '''
text=text[:section_start]+section+text[next_grid:]
front.write_text(text,encoding="utf-8")

c=css.read_text(encoding="utf-8-sig")
if "/* EPEN CLEAN V9 */" not in c:
    c += '''

/* EPEN CLEAN V9 */
.invoice-tariff-chart-view{position:static!important}
.invoice-tariff-selected-caption{display:none!important}
.tariff-saving-bar rect{fill:#2b9b70}
.tariff-saving-bar.selected rect{fill:#116b49}
.invoice-tariff-legend{display:flex;justify-content:flex-end;padding:2px 26px 0;font-size:11px;color:#475569}
.invoice-tariff-legend span{display:flex;align-items:center;gap:7px}
.invoice-tariff-legend i{width:13px;height:13px;border-radius:4px;background:#2b9b70}
.invoice-tariff-no-data{height:330px;display:grid;place-content:center;text-align:center;gap:5px;color:#64748b}
.invoice-tariff-no-data b{font-size:15px;color:#334155}
.invoice-tariff-no-data span{font-size:11px}
'''
css.write_text(c,encoding="utf-8")

print("OK")
print("Backup:", backup_dir)
print("TariffSavingTrend definitions:", text.count("function TariffSavingTrend("))
print("InvoiceTrend definitions:", text.count("function InvoiceTrend("))
