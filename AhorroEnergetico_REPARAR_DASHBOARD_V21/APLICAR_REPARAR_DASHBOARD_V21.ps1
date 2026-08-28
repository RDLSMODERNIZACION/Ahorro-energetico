$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - REPARAR DASHBOARD V21" -ForegroundColor Cyan
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

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_reparar_dashboard_v21_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

$startMarker='{tab==="dashboard"&&<>'
$nextMarker='{tab==="invoices"&&'

$start=$page.IndexOf($startMarker)
$next=$page.IndexOf($nextMarker)

if($start -lt 0){throw "No encontre el inicio del dashboard."}
if($next -lt 0){throw "No encontre el inicio de la pestaña Facturas."}
if($next -le $start){throw "La estructura de tabs esta dañada y no puedo reemplazar de forma segura."}

$dashboard=@'
{tab==="dashboard"&&<>
  <div className="kpis">
    <article>
      <span>Gasto histórico</span>
      <strong>{money.format(total)}</strong>
      <small>{invoices.length} facturas cargadas</small>
    </article>
    <article>
      <span>Consumo histórico</span>
      <strong>{number.format(kwh)} <i>kWh</i></strong>
      <small>energía activa registrada</small>
    </article>
    <article>
      <span>Ahorro potencial</span>
      <strong>{money.format(tariffAnnual)}</strong>
      <small>proyección anual</small>
    </article>
    <article className="green">
      <span>Ahorro mensual potencial</span>
      <strong>{money.format(tariffAnnual/12)}</strong>
      <small>estimación actual</small>
    </article>
  </div>

  <section className="panel executive-savings">
    <Title
      title="Desglose del ahorro potencial"
      sub="Cálculo actualizado con potencia usada, cuadro tarifario y 30% de IVA"
    />
    <div className="dashboard-savings-grid">
      <article className="power">
        <span>Potencia contratada</span>
        <strong>{money.format(powerAnnual)}</strong>
        <small>{money.format(powerAnnual/12)} mensual</small>
        <p>Contratada menos máxima registrada, sin margen.</p>
      </article>
      <article className="reactive">
        <span>Factor de potencia</span>
        <strong>{money.format(reactiveAnnual)}</strong>
        <small>{money.format(reactiveAnnual/12)} mensual</small>
        <p>Recargos COS que podrían evitarse.</p>
      </article>
      <article className="rate">
        <span>Cambio tarifario</span>
        <strong>{money.format(rateAnnual)}</strong>
        <small>{money.format(rateAnnual/12)} mensual</small>
        <p>{(tariffSavings.length||assessments.length)?"Diferencia contra la categoría que corresponde.":"Pendiente: el backend no devolvió el análisis tarifario."}</p>
      </article>
      <article className="saving-total">
        <span>Ahorro total propuesto</span>
        <strong>{money.format(tariffAnnual)}</strong>
        <small>{money.format(tariffAnnual/12)} mensual</small>
        <p>Proyección anual con IVA incluido.</p>
      </article>
    </div>
  </section>

  <MeterLifecyclePanel
    meters={lifecycleMeters}
    latestPeriod={periods[0]||""}
    onStatus={updateMeterStatus}
  />
</>}

'@

$page=$page.Substring(0,$start)+$dashboard+$page.Substring($next)

Set-Content $pagePath $page -Encoding UTF8

# Limpiar caches de Vite.
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificaciones simples.
$check=Get-Content $pagePath -Raw

$hasDashboard=$check -match '\{tab==="dashboard"&&<>'
$hasClose=$check -match '</>\}\s*\{tab==="invoices"&&'
$removedState=$check -notmatch 'Estado del análisis'
$removedMonthly=$check -notmatch 'Alertas mensuales'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Dashboard encontrado:          $hasDashboard"
Write-Host "  Fragmento cerrado antes Facturas: $hasClose"
Write-Host "  Estado del analisis eliminado: $removedState"
Write-Host "  Alertas mensuales eliminadas:  $removedMonthly"

if(-not ($hasDashboard -and $hasClose)){
  throw "La verificacion estructural del dashboard fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V21 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Reconstrui completo el bloque Resumen para corregir los cierres JSX." -ForegroundColor Green
Write-Host "Estado del analisis y Alertas mensuales siguen fuera del Resumen." -ForegroundColor Green
Write-Host ""
Write-Host "Backup:" -ForegroundColor DarkGray
Write-Host "  $backup" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Ahora ejecuta:" -ForegroundColor Cyan
Write-Host "  cd `"$front`"" -ForegroundColor White
Write-Host "  npm run dev" -ForegroundColor White

Read-Host "ENTER para cerrar"
