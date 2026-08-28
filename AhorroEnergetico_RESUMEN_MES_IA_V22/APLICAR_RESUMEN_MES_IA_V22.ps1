$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - RESUMEN MES + IA V22" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@(
  $here,
  (Join-Path $here "front"),
  (Split-Path -Parent $here),
  (Join-Path (Split-Path -Parent $here) "front")
) | Select-Object -Unique

$front=$null
foreach($c in $candidates){
  if(Test-Path (Join-Path $c "app\page.tsx")){
    $front=$c
    break
  }
}
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_resumen_mes_ia_v22_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# ------------------------------------------------------------
# 1. Agrega calculos DEL ULTIMO MES DISPONIBLE.
# ------------------------------------------------------------
if($page -notmatch 'const dashboardPeriod='){
  $anchor='const openMeter=(i:Invoice)=>'
  $idx=$page.IndexOf($anchor)
  if($idx -lt 0){throw "No encontre openMeter para insertar calculos del resumen."}

  $calc=@'
  const dashboardPeriod=periods[0]||"";
  const dashboardPeriodLabel=dashboardPeriod?new Date(Number(dashboardPeriod.slice(0,4)),Number(dashboardPeriod.slice(5,7))-1,1).toLocaleString("es-AR",{month:"long",year:"numeric"}):"Sin período";
  const dashboardInvoices=invoices.filter(i=>invoiceMonth(i)===dashboardPeriod);
  const dashboardPresentIds=new Set(dashboardInvoices.map(i=>i.meter_id));
  const dashboardReceived=[...dashboardPresentIds].filter(id=>activeMeters.some(m=>m.id===id)).length;
  const dashboardMissing=activeMeters.filter(m=>!dashboardPresentIds.has(m.id));
  const dashboardPowerMonthly=dashboardInvoices.reduce((sum,i)=>sum+invoicePowerSaving(i).amount,0);
  const dashboardReactiveMonthly=dashboardInvoices.reduce((sum,i)=>sum+invoiceReactiveSaving(i),0);
  const dashboardRateMonthly=tariffSavings.filter(x=>String(x.billing_period).slice(0,7)===dashboardPeriod).reduce((sum,x)=>sum+Number(x.monthly_saving_with_vat||0),0);
  const dashboardTotalMonthly=dashboardPowerMonthly+dashboardReactiveMonthly+dashboardRateMonthly;
  const dashboardOpportunityIds=new Set<string>();
  for(const i of dashboardInvoices){
    const hasPower=invoicePowerSaving(i).amount>0;
    const hasReactive=invoiceReactiveSaving(i)>0;
    const hasTariff=tariffSavings.some(x=>x.meter_id===i.meter_id&&String(x.billing_period).slice(0,7)===dashboardPeriod&&Number(x.monthly_saving_with_vat||0)>0);
    if(hasPower||hasReactive||hasTariff)dashboardOpportunityIds.add(i.meter_id);
  }
  const dashboardLowPf=dashboardInvoices.filter(i=>{const p=metrics(i).pf;return p>0&&p<.95}).length;
  const dashboardPowerExcess=dashboardInvoices.filter(i=>metrics(i).excess>0).length;

'@
  $page=$page.Insert($idx,$calc)
  Write-Host "[OK] Calculos del ultimo mes agregados." -ForegroundColor Green
}else{
  Write-Host "[OK] Calculos del resumen mensual ya existen." -ForegroundColor DarkGreen
}

# ------------------------------------------------------------
# 2. Reconstruye COMPLETO el dashboard para evitar cierres JSX.
# ------------------------------------------------------------
$startMarker='{tab==="dashboard"&&<>'
$nextMarker='{tab==="invoices"&&'
$start=$page.IndexOf($startMarker)
$next=$page.IndexOf($nextMarker)

if($start -lt 0){throw "No encontre el inicio del dashboard."}
if($next -lt 0 -or $next -le $start){throw "No encontre correctamente el inicio de Facturas."}

$dashboard=@'
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
      <span>Facturas faltantes</span>
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
      <small>{money.format(dashboardTotalMonthly*12)} anualizado ×12</small>
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
      sub={`Valores calculados sobre ${dashboardPeriodLabel}. El anual es una proyección del ahorro mensual × 12, con 30% de IVA.`}
    />
    <div className="dashboard-savings-grid">
      <article className="power">
        <span>Potencia contratada</span>
        <strong>{money.format(dashboardPowerMonthly*12)}</strong>
        <small>{money.format(dashboardPowerMonthly)} mensual · {dashboardPeriodLabel}</small>
        <p>Contratada menos máxima registrada del período, sin margen.</p>
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
        <p>Diferencia contra la categoría recomendada para ese período.</p>
      </article>
      <article className="saving-total">
        <span>Ahorro total propuesto</span>
        <strong>{money.format(dashboardTotalMonthly*12)}</strong>
        <small>{money.format(dashboardTotalMonthly)} mensual · {dashboardPeriodLabel}</small>
        <p>Proyección anual basada únicamente en el ahorro detectado del mes.</p>
      </article>
    </div>
  </section>
</>}

'@

$page=$page.Substring(0,$start)+$dashboard+$page.Substring($next)
Set-Content $pagePath $page -Encoding UTF8
Write-Host "[OK] Resumen reconstruido con foco en el mes actual." -ForegroundColor Green

# ------------------------------------------------------------
# 3. CSS profesional.
# ------------------------------------------------------------
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === RESUMEN MES IA V22 START === \*/.*?/\* === RESUMEN MES IA V22 END === \*/','')

$block=@'

/* === RESUMEN MES IA V22 START === */
.dashboard-ai-ask{
  display:grid;
  grid-template-columns:minmax(320px,.75fr) minmax(450px,1.25fr);
  gap:22px;
  align-items:center;
  padding:22px 24px;
  margin-bottom:15px;
  background:linear-gradient(135deg,#153f31,#1e7653);
  color:white;
  border:0;
}
.dashboard-ai-copy>span{font-size:8px;letter-spacing:.13em;font-weight:850;color:#9fddc0}
.dashboard-ai-copy h2{font-size:21px;margin:7px 0 5px}
.dashboard-ai-copy p{margin:0;color:#c7e5d7;font-size:9px;line-height:1.5}
.dashboard-ai-query{display:grid;grid-template-columns:1fr auto;gap:8px;background:#ffffff12;padding:8px;border-radius:11px;border:1px solid #ffffff1e}
.dashboard-ai-query input{height:43px;border:0;border-radius:8px;background:white;padding:0 13px;font:inherit;font-size:10px;color:#25382f;outline:none}
.dashboard-ai-query button{border:0;border-radius:8px;background:#61d69b;color:#103b2b;padding:0 17px;font-weight:900;cursor:pointer;white-space:nowrap}
.dashboard-ai-query button:disabled{opacity:.55}

.dashboard-month-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:12px}
.dashboard-month-kpis article{background:white;border:1px solid var(--line);border-radius:11px;padding:17px 18px}
.dashboard-month-kpis span{display:block;color:#718078;font-size:9px;font-weight:750}
.dashboard-month-kpis strong{display:block;font-size:25px;margin:8px 0 5px;letter-spacing:-.025em}
.dashboard-month-kpis strong i{font-size:13px;color:#78877f;font-style:normal;font-weight:700}
.dashboard-month-kpis small{font-size:8px;color:#87948d}
.dashboard-month-kpis .received strong{color:#157d55}
.dashboard-month-kpis .missing{background:#fff4f1;border-color:#efc7bd}.dashboard-month-kpis .missing strong{color:#c94c39}
.dashboard-month-kpis .ok{background:#edf8f2}.dashboard-month-kpis .ok strong{color:#16875a}
.dashboard-month-kpis .opportunities{background:#f8faf9}.dashboard-month-kpis .opportunities strong{color:#276b50}
.dashboard-month-kpis .saving{background:#1d8f5d;border-color:#1d8f5d;color:white}.dashboard-month-kpis .saving span,.dashboard-month-kpis .saving small{color:#c8eedb}.dashboard-month-kpis .saving strong{color:white}

.dashboard-period-strip{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:15px;padding:11px 14px;background:#f8faf9;border:1px solid var(--line);border-radius:9px;font-size:8px;color:#64766d}
.dashboard-period-strip b{color:#24382e;margin-right:4px;font-size:9px}
.dashboard-period-strip span{padding:5px 8px;border-radius:20px;background:white;border:1px solid #e0e8e3}

.executive-savings .panel-title h2{text-transform:none}
.executive-savings .panel-title p{max-width:820px}

@media(max-width:1150px){
  .dashboard-ai-ask{grid-template-columns:1fr}
  .dashboard-month-kpis{grid-template-columns:repeat(2,1fr)}
}
@media(max-width:650px){
  .dashboard-month-kpis{grid-template-columns:1fr}
  .dashboard-ai-query{grid-template-columns:1fr}
  .dashboard-ai-query button{height:41px}
}
/* === RESUMEN MES IA V22 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# ------------------------------------------------------------
# 4. Limpia cache y verifica.
# ------------------------------------------------------------
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
$okDashboard=$check -match 'dashboard-ai-ask'
$okPeriod=$check -match 'dashboardPeriodLabel'
$okClose=$check -match '</>\}\s*\{tab==="invoices"&&'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  IA arriba:            $okDashboard"
Write-Host "  Periodo mensual:      $okPeriod"
Write-Host "  Dashboard bien cerrado: $okClose"

if(-not ($okDashboard -and $okPeriod -and $okClose)){
  throw "La verificacion estructural fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V22 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "El Resumen queda enfocado en el ultimo mes disponible:" -ForegroundColor White
Write-Host " - Pregunta rapida a IA arriba" -ForegroundColor Green
Write-Host " - Facturas recibidas" -ForegroundColor Green
Write-Host " - Facturas faltantes" -ForegroundColor Green
Write-Host " - Suministros con oportunidad" -ForegroundColor Green
Write-Host " - Ahorro mensual potencial" -ForegroundColor Green
Write-Host " - Desglose del ahorro del mismo mes" -ForegroundColor Green
Write-Host ""
Write-Host "Se eliminaron del Resumen los indicadores historicos." -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup:" -ForegroundColor DarkGray
Write-Host "  $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
