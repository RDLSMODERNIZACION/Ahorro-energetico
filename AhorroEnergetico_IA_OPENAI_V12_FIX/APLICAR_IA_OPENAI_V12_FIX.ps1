$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - OPENAI V12 FIX ROBUSTO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$here=(Get-Location).Path
$candidates=@($here,(Split-Path -Parent $here))|Select-Object -Unique
$root=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "front\app\page.tsx")) -and
     (Test-Path (Join-Path $c "back\app\main.py"))){
    $root=$c;break
  }
}
if(-not $root){throw "No encontre la raiz Ahorro-energetico con front y back."}

$front=Join-Path $root "front"
$back=Join-Path $root "back"
$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"
$mainPath=Join-Path $back "app\main.py"
$aiTarget=Join-Path $back "app\routers\ai.py"

Write-Host "[OK] Proyecto:" -ForegroundColor Green
Write-Host "  $root" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_ia_openai_v12_fix_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force
Copy-Item $mainPath (Join-Path $backup "main.py") -Force
if(Test-Path $aiTarget){Copy-Item $aiTarget (Join-Path $backup "ai.py") -Force}

# ----------------------------------------------------------------
# BACKEND: si el primer V12 ya lo dejó listo, lo respetamos.
# ----------------------------------------------------------------
$sourceAi=Join-Path $scriptDir "ai.py"
if(Test-Path $sourceAi){
  Copy-Item $sourceAi $aiTarget -Force
  Write-Host "[OK] Router IA/OpenAI instalado/actualizado." -ForegroundColor Green
}

$main=Get-Content $mainPath -Raw

if($main -notmatch 'from \.routers import .*ai'){
  $main=$main -replace 'from \.routers import ([^\r\n]+)', {
    param($m)
    $line=$m.Value
    if($line -match '\bai\b'){return $line}
    return $line.TrimEnd()+",ai"
  }
}

if($main -notmatch 'include_router\(ai\.router'){
  $anchor='api.include_router(analysis.router,prefix="/api")'
  if($main.Contains($anchor)){
    $main=$main.Replace($anchor,$anchor+"`r`n"+'api.include_router(ai.router,prefix="/api")')
  }else{
    throw "No encontre include_router de analysis en main.py."
  }
}

Set-Content $mainPath $main -Encoding UTF8
Write-Host "[OK] Backend /api/ai/query verificado." -ForegroundColor Green

# ----------------------------------------------------------------
# FRONT: crea/normaliza modulo IA completo aunque V11 no esté.
# ----------------------------------------------------------------
$page=Get-Content $pagePath -Raw

# 1. Tipo del tab
if($page -match 'useState<"dashboard"\|"invoices"\|"framing"\|"tariffs"\|"map">'){
  $page=$page -replace 'useState<"dashboard"\|"invoices"\|"framing"\|"tariffs"\|"map">','useState<"dashboard"|"invoices"|"framing"|"tariffs"|"map"|"ai">'
}

# 2. Estados IA
if($page -notmatch '\[aiQuery,setAiQuery\]'){
  $anchor='const fileRef=useRef<HTMLInputElement>(null);'
  if($page.Contains($anchor)){
    $states='const[aiQuery,setAiQuery]=useState(""),[aiAnswer,setAiAnswer]=useState("Seleccioná una consulta sugerida o escribí qué querés analizar."),[aiBusy,setAiBusy]=useState(false);'+"`r`n  "
    $page=$page.Replace($anchor,$states+$anchor)
    Write-Host "[OK] Estados IA agregados." -ForegroundColor Green
  }else{
    throw "No encontre fileRef para agregar estados IA."
  }
}

# 3. Elimina cualquier runAiQuery viejo y agrega uno nuevo antes de updateMeterStatus
$page=[regex]::Replace(
  $page,
  '(?s)\s*function runAiQuery\(text\?:string\)\{.*?\n\s*\}\n(?=\s*async function updateMeterStatus)',
  "`r`n"
)
$page=[regex]::Replace(
  $page,
  '(?s)\s*async function runAiQuery\(text\?:string\)\{.*?\n\s*\}\n(?=\s*async function updateMeterStatus)',
  "`r`n"
)

$anchorFn='async function updateMeterStatus'
$idx=$page.IndexOf($anchorFn)
if($idx -lt 0){throw "No encontre updateMeterStatus para insertar runAiQuery."}

$fn=@'
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

'@
$page=$page.Insert($idx,$fn)
Write-Host "[OK] runAiQuery conectado a OpenAI." -ForegroundColor Green

# 4. Boton IA en sidebar si falta
if($page -notmatch '<span>IA</span>'){
  $navClose='</nav>'
  $iaButton='<button className={tab==="ai"?"active":""} onClick={()=>setTab("ai")}><i>✦</i><span>IA</span></button>'
  $navPos=$page.IndexOf($navClose)
  if($navPos -lt 0){throw "No encontre </nav> en sidebar."}
  $page=$page.Insert($navPos,$iaButton)
  Write-Host "[OK] Boton IA agregado al sidebar." -ForegroundColor Green
}else{
  Write-Host "[OK] Boton IA ya existe." -ForegroundColor DarkGreen
}

# 5. Vista IA completa si falta
if($page -notmatch 'tab==="ai"&&'){
  $anchorView='{tab==="map"&&'
  $pos=$page.IndexOf($anchorView)
  if($pos -lt 0){throw "No encontre la vista map para insertar IA."}

$view=@'
  {tab==="ai"&&<div className="ai-module">
    <section className="panel ai-hero">
      <div>
        <span className="ai-kicker">ASISTENTE DE GESTIÓN ENERGÉTICA</span>
        <h2>IA conectada a OpenAI + Supabase</h2>
        <p>Preguntá en lenguaje natural sobre facturas, consumo, potencia, cos φ, faltantes y oportunidades de ahorro.</p>
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
        <div><h2>Preguntale a la base</h2><p>Conectado al backend, Supabase y OpenAI.</p></div>
      </div>

      <div className="ai-suggestions">
        {[
          "¿Qué medidores tienen cos φ bajo y cuáles son los peores?",
          "¿Dónde sobra más potencia contratada?",
          "¿Qué facturas faltan este mes?",
          "¿Cuáles son las mayores oportunidades de ahorro?",
          "¿Cuáles son los mayores consumos?",
          "Haceme un resumen ejecutivo del último mes"
        ].map(q=><button key={q} onClick={()=>{setAiQuery(q);runAiQuery(q)}}>{q}</button>)}
      </div>

      <div className="ai-answer">
        <div className="ai-avatar">✦</div>
        <div><b>Asistente energético</b><p>{aiBusy?"Analizando Supabase con OpenAI…":aiAnswer}</p></div>
      </div>

      <div className="ai-input-row">
        <input value={aiQuery} onChange={e=>setAiQuery(e.target.value)} onKeyDown={e=>{if(e.key==="Enter")runAiQuery()}} placeholder="Ej.: ¿Qué medidores conviene revisar primero y por qué?"/>
        <button onClick={()=>runAiQuery()} disabled={aiBusy}>{aiBusy?"Analizando…":"Consultar IA"}</button>
      </div>
    </section>
  </div>}

'@
  $page=$page.Insert($pos,$view)
  Write-Host "[OK] Vista IA agregada." -ForegroundColor Green
}else{
  Write-Host "[OK] Vista IA ya existe." -ForegroundColor DarkGreen
  $page=$page.Replace(
    'Primera versión: consultas inteligentes sobre los datos ya cargados.',
    'Conectado al backend, Supabase y OpenAI.'
  )
}

Set-Content $pagePath $page -Encoding UTF8

# 6. CSS si falta
$css=Get-Content $cssPath -Raw
if($css -notmatch 'MODULO IA V11 START'){
$block=@'

/* === MODULO IA V11 START === */
.ai-module{display:grid;gap:15px}
.ai-hero{display:flex;justify-content:space-between;align-items:center;padding:24px 26px;background:linear-gradient(145deg,#153f31,#1b704f);color:white}
.ai-kicker{font-size:8px;letter-spacing:.14em;color:#a8dbc3;font-weight:800}.ai-hero h2{font-size:24px;margin:7px 0}.ai-hero p{margin:0;color:#c4e2d4;font-size:10px}.ai-badge{width:74px;height:74px;border-radius:18px;background:#ffffff14;border:1px solid #ffffff22;display:grid;place-items:center;font-size:20px;font-weight:900}
.ai-alert-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.ai-alert-grid article{background:white;border:1px solid var(--line);border-radius:11px;padding:17px}.ai-alert-grid span{display:block;color:#75847c;font-size:9px;font-weight:750}.ai-alert-grid b{display:block;font-size:24px;margin:8px 0 5px}.ai-alert-grid small{font-size:8px;color:#8a9891}.ai-alert-grid .green{background:#eaf7f0;border-color:#c9e6d7}.ai-alert-grid .green b{color:#16875a}
.ai-chat{overflow:hidden}.ai-chat-head{padding:18px 20px;border-bottom:1px solid var(--line)}.ai-chat-head h2{font-size:14px;margin:0}.ai-chat-head p{font-size:9px;color:#75847c;margin:4px 0 0}
.ai-suggestions{display:flex;flex-wrap:wrap;gap:7px;padding:14px 18px;background:#f8faf9;border-bottom:1px solid var(--line)}.ai-suggestions button{border:1px solid #d7e4dc;background:white;color:#2c7053;border-radius:20px;padding:8px 11px;font-size:9px;font-weight:750;cursor:pointer}
.ai-answer{display:flex;gap:12px;padding:22px 20px;min-height:150px;align-items:flex-start}.ai-avatar{width:34px;height:34px;border-radius:10px;background:#173f31;color:#7fe1ae;display:grid;place-items:center;font-size:16px;flex:0 0 34px}.ai-answer b{font-size:10px}.ai-answer p{white-space:pre-wrap;font-size:11px;line-height:1.65;color:#4f6258;margin:7px 0 0}
.ai-input-row{display:grid;grid-template-columns:1fr auto;gap:9px;padding:15px 18px;border-top:1px solid var(--line);background:#fbfdfc}.ai-input-row input{height:42px;border:1px solid #d8e3dd;border-radius:9px;padding:0 13px;font:inherit;font-size:10px}.ai-input-row button{border:0;background:#188b5b;color:white;border-radius:9px;padding:0 18px;font-weight:800;cursor:pointer}.ai-input-row button:disabled{opacity:.55}
@media(max-width:1100px){.ai-alert-grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:650px){.ai-alert-grid{grid-template-columns:1fr}.ai-hero{align-items:flex-start}.ai-badge{width:52px;height:52px}.ai-input-row{grid-template-columns:1fr}.ai-input-row button{height:40px}}
/* === MODULO IA V11 END === */
'@
  $css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
  Set-Content $cssPath $css -Encoding UTF8
  Write-Host "[OK] CSS IA agregado." -ForegroundColor Green
}

# Caches
foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificacion
$p=Get-Content $pagePath -Raw
$m=Get-Content $mainPath -Raw
if(($p -match '"/api/ai/query"') -and ($p -match '<span>IA</span>') -and ($p -match 'tab==="ai"') -and ($m -match 'include_router\(ai\.router')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V12 FIX APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora SI quedaron:" -ForegroundColor White
  Write-Host " - Boton IA en sidebar" -ForegroundColor Green
  Write-Host " - Pantalla IA" -ForegroundColor Green
  Write-Host " - Front llamando /api/ai/query" -ForegroundColor Green
  Write-Host " - Backend conectado a OpenAI" -ForegroundColor Green
  Write-Host ""
  Write-Host "Falta configurar OPENAI_API_KEY en el backend." -ForegroundColor Yellow
  Write-Host "NO pegues la clave en el front." -ForegroundColor Red
  Write-Host ""
  Write-Host "LOCAL:" -ForegroundColor Cyan
  Write-Host '  $env:OPENAI_API_KEY="TU_CLAVE_OPENAI"' -ForegroundColor White
  Write-Host '  $env:OPENAI_MODEL="gpt-5.4"' -ForegroundColor White
  Write-Host "  cd `"$back`"" -ForegroundColor White
  Write-Host "  uvicorn app.main:app --reload" -ForegroundColor White
  Write-Host ""
  Write-Host "Luego otra terminal:" -ForegroundColor Cyan
  Write-Host "  cd `"$front`"" -ForegroundColor White
  Write-Host "  npm run dev" -ForegroundColor White
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
