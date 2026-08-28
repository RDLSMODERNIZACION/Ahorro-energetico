$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - ALERTAS IA V15" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$front=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))){
    $front=$c;break
  }
}
if(-not $front){throw "No encontre la carpeta front."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ia_alertas_v15_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# Inserta cálculos derivados para alertas, si no existen.
if($page -notmatch 'const aiAlertData=useMemo'){
  $anchor='const openMeter=(i:Invoice)=>{setSelectedInvoice(i);setSelectedMeter(i.meter_id)};'
  if(-not $page.Contains($anchor)){throw "No encontre openMeter para insertar calculos IA."}

  $logic=@'
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
        critical.push({kind:"pf",score:(.95-x.pf)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`Cos φ ${x.pf.toFixed(3)} · revisar compensación reactiva`,invoice:i});
      }
      if(avgKwh>0&&x.kwh>avgKwh*1.3){
        critical.push({kind:"consumption",score:(x.kwh/avgKwh-1)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`Consumo +${((x.kwh/avgKwh-1)*100).toFixed(0)}% vs promedio 6 meses`,invoice:i});
      }
      if(avgAmount>0&&currentAmount>avgAmount*1.35){
        critical.push({kind:"amount",score:(currentAmount/avgAmount-1)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`Importe +${((currentAmount/avgAmount-1)*100).toFixed(0)}% vs promedio`,invoice:i});
      }

      if(x.excess>0){
        const monthly=invoicePowerSaving(i).amount;
        opportunities.push({kind:"power",value:monthly,label:m?.service_name||m?.meter_number||"Medidor",detail:`${number.format(x.excess)} kW sobrantes · ${money.format(monthly)}/mes`,invoice:i});
      }
      const reactive=invoiceReactiveSaving(i);
      if(reactive>0){
        opportunities.push({kind:"reactive",value:reactive,label:m?.service_name||m?.meter_number||"Medidor",detail:`Penalización reactiva evitable · ${money.format(reactive)}/mes`,invoice:i});
      }
      const tariff=tariffSavings.find(t=>t.meter_id===i.meter_id&&String(t.billing_period).slice(0,7)===latest);
      if(Number(tariff?.monthly_saving_with_vat||0)>0){
        opportunities.push({kind:"tariff",value:Number(tariff?.monthly_saving_with_vat||0),label:m?.service_name||m?.meter_number||"Medidor",detail:`Cambio tarifario · ${money.format(Number(tariff?.monthly_saving_with_vat||0))}/mes`,invoice:i});
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
          changes.push({label:m?.service_name||m?.meter_number||"Medidor",detail:bits.join(" · "),positive:consumptionDelta<0&&amountDelta<0,invoice:i});
        }
      }
    }

    for(const m of missingPeriodMeters){
      critical.push({kind:"missing",score:60,label:m.service_name||m.meter_number||"Medidor",detail:`Factura faltante en ${controlPeriod||latest}`,invoice:null});
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

'@
  $page=$page.Replace($anchor,$logic+$anchor)
  Write-Host "[OK] Motor local de alertas inteligentes agregado." -ForegroundColor Green
}

# Inserta tarjetas dentro del modulo IA, antes del chat.
if($page -notmatch 'ai-smart-sections'){
  $anchor='<section className="panel ai-chat">'
  if(-not $page.Contains($anchor)){throw "No encontre ai-chat. Aplica primero V11/V12 FIX."}

  $sections=@'
    <div className="ai-smart-sections">
      <section className="panel ai-smart-card critical">
        <div className="ai-smart-head"><div><span>ALERTAS CRÍTICAS</span><h3>Qué revisar ahora</h3></div><b>{aiAlertData.criticalCount}</b></div>
        <div className="ai-smart-list">
          {aiAlertData.critical.length?aiAlertData.critical.map((a,index)=><button key={`${a.kind}-${index}`} onClick={()=>a.invoice&&openMeter(a.invoice)}>
            <i>!</i><div><b>{a.label}</b><span>{a.detail}</span></div><em>Revisar</em>
          </button>):<div className="ai-smart-empty">No hay alertas críticas para el último período.</div>}
        </div>
      </section>

      <section className="panel ai-smart-card opportunities">
        <div className="ai-smart-head"><div><span>TOP OPORTUNIDADES</span><h3>Dónde hay más ahorro</h3></div><b>{aiAlertData.opportunityCount}</b></div>
        <div className="ai-smart-list">
          {aiAlertData.opportunities.length?aiAlertData.opportunities.map((a,index)=><button key={`${a.kind}-${index}`} onClick={()=>a.invoice&&openMeter(a.invoice)}>
            <i>$</i><div><b>{a.label}</b><span>{a.detail}</span></div><em>{money.format(a.value)}</em>
          </button>):<div className="ai-smart-empty">No hay oportunidades valorizadas en el último período.</div>}
        </div>
      </section>

      <section className="panel ai-smart-card changes">
        <div className="ai-smart-head"><div><span>QUÉ CAMBIÓ ESTE MES</span><h3>Variaciones relevantes</h3></div><b>{aiAlertData.changes.length}</b></div>
        <div className="ai-smart-list">
          {aiAlertData.changes.length?aiAlertData.changes.map((a,index)=><button key={index} onClick={()=>a.invoice&&openMeter(a.invoice)}>
            <i>{a.positive?"↓":"↕"}</i><div><b>{a.label}</b><span>{a.detail}</span></div><em className={a.positive?"positive":""}>{a.positive?"Mejora":"Cambio"}</em>
          </button>):<div className="ai-smart-empty">No se detectaron cambios superiores al 20% contra el mes anterior.</div>}
        </div>
      </section>
    </div>

'@
  $page=$page.Replace($anchor,$sections+$anchor)
  Write-Host "[OK] Alertas críticas, oportunidades y cambios agregados." -ForegroundColor Green
}

# Agrega sugerencias específicas al chat si no están.
$page=$page.Replace(
  '"Haceme un resumen ejecutivo del último mes"',
  '"Haceme un resumen ejecutivo del último mes","Analizá las alertas críticas y decime qué atender primero","Compará los últimos 6 meses y detectá mejoras y deterioros"'
)

Set-Content $pagePath $page -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === IA ALERTAS V15 START === \*/.*?/\* === IA ALERTAS V15 END === \*/','')
$block=@'

/* === IA ALERTAS V15 START === */
.ai-smart-sections{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}
.ai-smart-card{overflow:hidden}.ai-smart-head{display:flex;justify-content:space-between;align-items:center;padding:16px 17px;border-bottom:1px solid var(--line)}.ai-smart-head span{display:block;font-size:7px;letter-spacing:.1em;font-weight:850;color:#7a8982}.ai-smart-head h3{font-size:12px;margin:4px 0 0}.ai-smart-head>b{font-size:23px;color:#33463d}
.ai-smart-card.critical .ai-smart-head{background:#fff5f2}.ai-smart-card.critical .ai-smart-head>b{color:#c94837}.ai-smart-card.opportunities .ai-smart-head{background:#eef8f3}.ai-smart-card.opportunities .ai-smart-head>b{color:#158255}.ai-smart-card.changes .ai-smart-head{background:#f5f8fa}.ai-smart-card.changes .ai-smart-head>b{color:#376b8b}
.ai-smart-list{max-height:370px;overflow:auto}.ai-smart-list>button{width:100%;border:0;border-bottom:1px solid #edf1ee;background:white;display:grid;grid-template-columns:29px 1fr auto;gap:10px;align-items:center;text-align:left;padding:12px 13px;cursor:pointer}.ai-smart-list>button:hover{background:#f8fbf9}.ai-smart-list>button>i{width:27px;height:27px;border-radius:8px;display:grid;place-items:center;font-style:normal;font-weight:900;background:#eef3f0;color:#44655a}.critical .ai-smart-list>button>i{background:#fff0ed;color:#c94b3a}.opportunities .ai-smart-list>button>i{background:#e7f6ee;color:#168659}.changes .ai-smart-list>button>i{background:#edf3f7;color:#477996}
.ai-smart-list>button div b,.ai-smart-list>button div span{display:block}.ai-smart-list>button div b{font-size:9px}.ai-smart-list>button div span{margin-top:4px;color:#72827a;font-size:8px;line-height:1.35}.ai-smart-list>button em{font-style:normal;font-size:8px;font-weight:850;color:#a94a3c;white-space:nowrap}.opportunities .ai-smart-list>button em{color:#168659}.changes .ai-smart-list>button em{color:#477996}.changes .ai-smart-list>button em.positive{color:#168659}
.ai-smart-empty{padding:24px 15px;text-align:center;color:#839189;font-size:9px}
@media(max-width:1200px){.ai-smart-sections{grid-template-columns:1fr}} 
/* === IA ALERTAS V15 END === */
'@
$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if(($check -match 'aiAlertData') -and ($check -match 'ALERTAS CRÍTICAS') -and ($check -match 'TOP OPORTUNIDADES')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " IA ALERTAS V15 APLICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "La pantalla IA ahora tiene:" -ForegroundColor White
  Write-Host " - Alertas críticas" -ForegroundColor Green
  Write-Host " - Top oportunidades de ahorro" -ForegroundColor Green
  Write-Host " - Qué cambió este mes" -ForegroundColor Green
  Write-Host " - Acceso al análisis individual tocando cada alerta" -ForegroundColor Green
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Reinicia:" -ForegroundColor Cyan
  Write-Host "  cd `"$front`"" -ForegroundColor White
  Write-Host "  npm run dev" -ForegroundColor White
  Write-Host "  Ctrl + F5" -ForegroundColor White
}else{throw "La verificacion final fallo."}

Read-Host "ENTER para cerrar"
