$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - MODULO IA EN SIDEBAR V11" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_ia_sidebar_v11_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# 1) Agrega "ai" al union type del tab.
$page=$page -replace 'useState<"dashboard"\|"invoices"\|"framing"\|"tariffs"\|"map">', 'useState<"dashboard"|"invoices"|"framing"|"tariffs"|"map"|"ai">'

# 2) Agrega estados del modulo IA si no existen.
if($page -notmatch '\[aiQuery,setAiQuery\]'){
  $anchor='const fileRef=useRef<HTMLInputElement>(null);'
  if($page.Contains($anchor)){
    $states='const[aiQuery,setAiQuery]=useState(""),[aiAnswer,setAiAnswer]=useState("Seleccioná una consulta sugerida o escribí qué querés analizar."),[aiBusy,setAiBusy]=useState(false);'+"`r`n  "
    $page=$page.Replace($anchor,$states+$anchor)
  }else{throw "No encontre el punto para agregar estados IA."}
}

# 3) Agrega funcion de consulta local inteligente.
if($page -notmatch 'function runAiQuery\('){
  $anchor='async function updateMeterStatus'
  $idx=$page.IndexOf($anchor)
  if($idx -lt 0){throw "No encontre funciones principales para insertar IA."}

  $fn=@'
  function runAiQuery(text?:string){
    const q=(text??aiQuery).trim().toLowerCase();
    if(!q){setAiAnswer("Escribí una consulta.");return}
    setAiBusy(true);
    try{
      const latest=periods[0]||"";
      const latestRows=invoices.filter(i=>invoiceMonth(i)===latest);
      const lowPf=latestRows.filter(i=>{const p=metrics(i).pf;return p>0&&p<.95}).sort((a,b)=>metrics(a).pf-metrics(b).pf);
      const powerExcess=latestRows.filter(i=>metrics(i).excess>0).sort((a,b)=>metrics(b).excess-metrics(a).excess);
      const topSaving=latestRows.map(i=>{
        const p=invoicePowerSaving(i).amount;
        const r=invoiceReactiveSaving(i);
        const t=tariffSavings.find(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===latest);
        return{i,saving:p+r+Number(t?.monthly_saving_with_vat||0)};
      }).filter(x=>x.saving>0).sort((a,b)=>b.saving-a.saving);

      let answer="";
      if(q.includes("cos")||q.includes("factor")||q.includes("reactiva")){
        answer=`Encontré ${lowPf.length} medidor(es) con cos φ menor a 0,95 en ${latest}. `+
          (lowPf.slice(0,5).map(i=>`${i.meters?.service_name||i.meters?.meter_number}: ${metrics(i).pf.toFixed(3)}`).join(" · ")||"No hay casos críticos.");
      }else if(q.includes("potencia")||q.includes("contratada")||q.includes("sobrante")){
        answer=`Hay ${powerExcess.length} medidor(es) con potencia contratada por encima de la demanda en ${latest}. `+
          (powerExcess.slice(0,5).map(i=>`${i.meters?.service_name||i.meters?.meter_number}: ${number.format(metrics(i).excess)} kW sobrantes`).join(" · ")||"No hay sobrantes.");
      }else if(q.includes("falt")||q.includes("sin factura")){
        answer=`Para ${controlPeriod||latest} hay ${missingPeriodMeters.length} factura(s) faltante(s). `+
          (missingPeriodMeters.slice(0,8).map(m=>`${m.service_name||m.meter_number}`).join(" · ")||"No faltan facturas.");
      }else if(q.includes("ahorro")||q.includes("prioridad")||q.includes("conviene")){
        answer=`Los principales ahorros mensuales detectados en ${latest} son: `+
          (topSaving.slice(0,5).map(x=>`${x.i.meters?.service_name||x.i.meters?.meter_number}: ${money.format(x.saving)}/mes`).join(" · ")||"No hay ahorros valorizados.");
      }else if(q.includes("consumo")||q.includes("mayor")){
        const top=[...latestRows].sort((a,b)=>metrics(b).kwh-metrics(a).kwh).slice(0,5);
        answer=`Los mayores consumos de ${latest}: `+top.map(i=>`${i.meters?.service_name||i.meters?.meter_number}: ${number.format(metrics(i).kwh)} kWh`).join(" · ");
      }else{
        answer=`Resumen de ${latest}: ${latestRows.length} facturas cargadas, ${missingPeriodMeters.length} faltantes, ${lowPf.length} con cos φ bajo, ${powerExcess.length} con potencia sobrante y ${topSaving.length} con ahorro valorizado.`;
      }
      setAiAnswer(answer);
    }finally{
      setAiBusy(false);
    }
  }

'@
  $page=$page.Insert($idx,$fn)
}

# 4) Agrega botón IA en sidebar.
if($page -notmatch '>IA</span>'){
  # Busca botón Medidores y agrega IA inmediatamente después.
  $pattern='(<button className=\{tab==="map"\?"active":""\} onClick=\{\(\)=>setTab\("map"\)\}>.*?<span>Medidores</span></button>)'
  if([regex]::IsMatch($page,$pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)){
    $button='$1<button className={tab==="ai"?"active":""} onClick={()=>setTab("ai")}><i>✦</i><span>IA</span></button>'
    $page=[regex]::Replace($page,$pattern,$button,1,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  }else{
    # Fallback: inserta antes de </nav>
    $navClose='</nav>'
    $iaButton='<button className={tab==="ai"?"active":""} onClick={()=>setTab("ai")}><i>✦</i><span>IA</span></button>'
    $pos=$page.IndexOf($navClose)
    if($pos -lt 0){throw "No encontre el sidebar/nav."}
    $page=$page.Insert($pos,$iaButton)
  }
  Write-Host "[OK] Boton IA agregado al sidebar." -ForegroundColor Green
}else{
  Write-Host "[OK] Boton IA ya existe." -ForegroundColor DarkGreen
}

# 5) Agrega vista IA antes de cierre principal de tabs.
if($page -notmatch 'tab==="ai"&&'){
  $anchor='{tab==="map"&&'
  $pos=$page.IndexOf($anchor)
  if($pos -lt 0){throw "No encontre la vista map para insertar IA."}

  # Insertamos IA antes de map para mantener orden.
  $view=@'
  {tab==="ai"&&<div className="ai-module">
    <section className="panel ai-hero">
      <div>
        <span className="ai-kicker">ASISTENTE DE GESTIÓN ENERGÉTICA</span>
        <h2>IA para analizar la base municipal</h2>
        <p>Consultá facturas, consumo, potencia, factor de potencia, faltantes y oportunidades de ahorro.</p>
      </div>
      <div className="ai-badge">✦ IA</div>
    </section>

    <div className="ai-alert-grid">
      <article><span>Facturas faltantes</span><b>{missingPeriodMeters.length}</b><small>{controlPeriod||periods[0]||"Sin período"}</small></article>
      <article><span>Cos φ bajo</span><b>{latestInvoiceByMeter.filter(i=>{const p=metrics(i).pf;return p>0&&p<.95}).length}</b><small>requieren revisión</small></article>
      <article><span>Potencia sobrante</span><b>{latestInvoiceByMeter.filter(i=>metrics(i).excess>0).length}</b><small>medidores detectados</small></article>
      <article className="green"><span>Ahorro anual potencial</span><b>{money.format(tariffAnnual)}</b><small>estimación actual</small></article>
    </div>

    <section className="panel ai-chat">
      <div className="ai-chat-head">
        <div><h2>Preguntale a la base</h2><p>Primera versión: consultas inteligentes sobre los datos ya cargados.</p></div>
      </div>

      <div className="ai-suggestions">
        {[
          "¿Qué medidores tienen cos φ bajo?",
          "¿Dónde sobra más potencia contratada?",
          "¿Qué facturas faltan este mes?",
          "¿Cuáles son los mayores ahorros?",
          "¿Cuáles son los mayores consumos?"
        ].map(q=><button key={q} onClick={()=>{setAiQuery(q);runAiQuery(q)}}>{q}</button>)}
      </div>

      <div className="ai-answer">
        <div className="ai-avatar">✦</div>
        <div><b>Asistente energético</b><p>{aiBusy?"Analizando la base…":aiAnswer}</p></div>
      </div>

      <div className="ai-input-row">
        <input value={aiQuery} onChange={e=>setAiQuery(e.target.value)} onKeyDown={e=>{if(e.key==="Enter")runAiQuery()}} placeholder="Ej.: ¿Qué medidores conviene revisar primero?"/>
        <button onClick={()=>runAiQuery()} disabled={aiBusy}>{aiBusy?"Analizando…":"Consultar"}</button>
      </div>
    </section>
  </div>}

'@
  $page=$page.Insert($pos,$view)
  Write-Host "[OK] Pantalla IA agregada." -ForegroundColor Green
}

Set-Content $pagePath $page -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === MODULO IA V11 START === \*/.*?/\* === MODULO IA V11 END === \*/','')
$block=@'

/* === MODULO IA V11 START === */
.ai-module{display:grid;gap:15px}
.ai-hero{display:flex;justify-content:space-between;align-items:center;padding:24px 26px;background:linear-gradient(145deg,#153f31,#1b704f);color:white}
.ai-kicker{font-size:8px;letter-spacing:.14em;color:#a8dbc3;font-weight:800}.ai-hero h2{font-size:24px;margin:7px 0}.ai-hero p{margin:0;color:#c4e2d4;font-size:10px}.ai-badge{width:74px;height:74px;border-radius:18px;background:#ffffff14;border:1px solid #ffffff22;display:grid;place-items:center;font-size:20px;font-weight:900}
.ai-alert-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.ai-alert-grid article{background:white;border:1px solid var(--line);border-radius:11px;padding:17px}.ai-alert-grid span{display:block;color:#75847c;font-size:9px;font-weight:750}.ai-alert-grid b{display:block;font-size:24px;margin:8px 0 5px}.ai-alert-grid small{font-size:8px;color:#8a9891}.ai-alert-grid .green{background:#eaf7f0;border-color:#c9e6d7}.ai-alert-grid .green b{color:#16875a}
.ai-chat{overflow:hidden}.ai-chat-head{padding:18px 20px;border-bottom:1px solid var(--line)}.ai-chat-head h2{font-size:14px;margin:0}.ai-chat-head p{font-size:9px;color:#75847c;margin:4px 0 0}
.ai-suggestions{display:flex;flex-wrap:wrap;gap:7px;padding:14px 18px;background:#f8faf9;border-bottom:1px solid var(--line)}.ai-suggestions button{border:1px solid #d7e4dc;background:white;color:#2c7053;border-radius:20px;padding:8px 11px;font-size:9px;font-weight:750;cursor:pointer}
.ai-answer{display:flex;gap:12px;padding:22px 20px;min-height:130px;align-items:flex-start}.ai-avatar{width:34px;height:34px;border-radius:10px;background:#173f31;color:#7fe1ae;display:grid;place-items:center;font-size:16px;flex:0 0 34px}.ai-answer b{font-size:10px}.ai-answer p{font-size:11px;line-height:1.65;color:#4f6258;margin:7px 0 0}
.ai-input-row{display:grid;grid-template-columns:1fr auto;gap:9px;padding:15px 18px;border-top:1px solid var(--line);background:#fbfdfc}.ai-input-row input{height:42px;border:1px solid #d8e3dd;border-radius:9px;padding:0 13px;font:inherit;font-size:10px}.ai-input-row button{border:0;background:#188b5b;color:white;border-radius:9px;padding:0 18px;font-weight:800;cursor:pointer}.ai-input-row button:disabled{opacity:.55}
@media(max-width:1100px){.ai-alert-grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:650px){.ai-alert-grid{grid-template-columns:1fr}.ai-hero{align-items:flex-start}.ai-badge{width:52px;height:52px}.ai-input-row{grid-template-columns:1fr}.ai-input-row button{height:40px}}
/* === MODULO IA V11 END === */
'@
$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if(($check -match 'tab==="ai"') -and ($check -match 'Asistente energético')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " MODULO IA V11 APLICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Se agrego IA a la sidebar y una primera pantalla funcional." -ForegroundColor Green
  Write-Host "Puede responder consultas sobre:" -ForegroundColor White
  Write-Host " - cos fi bajo" -ForegroundColor White
  Write-Host " - potencia sobrante" -ForegroundColor White
  Write-Host " - facturas faltantes" -ForegroundColor White
  Write-Host " - mayores ahorros" -ForegroundColor White
  Write-Host " - mayores consumos" -ForegroundColor White
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Reinicia:" -ForegroundColor Cyan
  Write-Host "  cd `"$front`"" -ForegroundColor White
  Write-Host "  npm run dev" -ForegroundColor White
  Write-Host "  Ctrl + F5" -ForegroundColor White
}else{throw "La verificacion final fallo."}

Read-Host "ENTER para cerrar"
