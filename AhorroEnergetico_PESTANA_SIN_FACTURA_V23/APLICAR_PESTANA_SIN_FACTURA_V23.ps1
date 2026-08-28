$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - PESTANA SIN FACTURA V23" -ForegroundColor Cyan
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
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))){
    $front=$c
    break
  }
}
if(-not $front){throw "No encontre la carpeta front."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_pestana_sin_factura_v23_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# ----------------------------------------------------------
# 1) Agrega tab "missing" al union type.
# ----------------------------------------------------------
$page=$page -replace 'useState<"dashboard"\|"invoices"\|"framing"\|"tariffs"\|"map"\|"ai">', 'useState<"dashboard"|"invoices"|"missing"|"framing"|"tariffs"|"map"|"ai">'
$page=$page -replace 'useState<"dashboard"\|"invoices"\|"framing"\|"tariffs"\|"map">', 'useState<"dashboard"|"invoices"|"missing"|"framing"|"tariffs"|"map">'

# ----------------------------------------------------------
# 2) Boton en sidebar, despues de Facturas.
# ----------------------------------------------------------
if($page -notmatch '<span>Sin factura</span>'){
  $pattern='(?s)(<button className=\{tab==="invoices"\?"active":""\} onClick=\{\(\)=>setTab\("invoices"\)\}>.*?<span>Facturas</span></button>)'
  $rx=New-Object System.Text.RegularExpressions.Regex($pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  if($rx.IsMatch($page)){
    $page=$rx.Replace($page,'$1<button className={tab==="missing"?"active":""} onClick={()=>setTab("missing")}><i>!</i><span>Sin factura</span></button>',1)
  }else{
    throw "No encontre el boton Facturas en sidebar."
  }
  Write-Host "[OK] Boton Sin factura agregado a sidebar." -ForegroundColor Green
}

# ----------------------------------------------------------
# 3) Quitar MeterLifecyclePanel del dashboard si sigue ahi.
# ----------------------------------------------------------
$page=[regex]::Replace(
  $page,
  '(?s)\s*<MeterLifecyclePanel\s+meters=\{lifecycleMeters\}\s+latestPeriod=\{periods\[0\]\|\|""\}\s+onStatus=\{updateMeterStatus\}\s*/>\s*',
  "`r`n"
)

# ----------------------------------------------------------
# 4) Crear vista "missing" antes de invoices.
# ----------------------------------------------------------
if($page -notmatch 'tab==="missing"&&'){
  $anchor='{tab==="invoices"&&'
  $pos=$page.IndexOf($anchor)
  if($pos -lt 0){throw "No encontre la vista Facturas."}

  $view=@'
  {tab==="missing"&&<div className="missing-tab-page">
    <section className="panel missing-tab-header">
      <div>
        <span className="missing-tab-kicker">SEGUIMIENTO DE FACTURACIÓN</span>
        <h2>Medidores sin factura</h2>
        <p>Listado separado de los suministros que no tienen facturación reciente. No se mezclan con las facturas recibidas.</p>
      </div>
      <div className="missing-tab-count">
        <b>{lifecycleMeters.length}</b>
        <span>medidores en seguimiento</span>
      </div>
    </section>

    <section className="panel missing-list-panel">
      <div className="missing-list-head">
        <span>Estado</span>
        <span>Medidor / ID</span>
        <span>Servicio</span>
        <span>Suministro</span>
        <span>Última factura</span>
        <span>Meses sin factura</span>
        <span>Acciones</span>
      </div>

      <div className="missing-list-body">
        {lifecycleMeters.map(m=>{
          const months=monthsBetween(m.last_seen_period,periods[0]||"");
          return <div className={`missing-list-row ${m.status==="removed"?"removed":"watch"}`} key={m.id}>
            <div>
              <span className={`missing-state ${m.status||"inactive"}`}>{m.status==="removed"?"BAJA CONFIRMADA":"POSIBLE BAJA"}</span>
            </div>
            <div>
              <b>Medidor {m.meter_number||"S/D"}</b>
              <small>{m.tracking_code||"Sin ID"}</small>
            </div>
            <div>
              <b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b>
              <small>{m.sites?.address||"Sin dirección registrada"}</small>
            </div>
            <div>
              <b>{m.supply_number||"S/D"}</b>
              <small>{m.current_tariff_code||"Sin tarifa"}</small>
            </div>
            <div>
              <b>{m.last_seen_period?.slice(0,7)||"S/D"}</b>
              <small>último período cargado</small>
            </div>
            <div>
              <b>{months}</b>
              <small>meses</small>
            </div>
            <div className="missing-list-actions">
              {m.status!=="removed"&&<button className="danger-btn" onClick={()=>updateMeterStatus(m.id,"removed")}>Confirmar baja</button>}
              <button className="ok-btn" onClick={()=>updateMeterStatus(m.id,"active")}>Continúa activo</button>
            </div>
          </div>
        })}
        {!lifecycleMeters.length&&<div className="missing-list-empty">No hay medidores sin facturación reciente.</div>}
      </div>
    </section>
  </div>}

'@
  $page=$page.Insert($pos,$view)
  Write-Host "[OK] Vista Sin factura agregada." -ForegroundColor Green
}

Set-Content $pagePath $page -Encoding UTF8

# ----------------------------------------------------------
# 5) CSS lista compacta.
# ----------------------------------------------------------
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === PESTANA SIN FACTURA V23 START === \*/.*?/\* === PESTANA SIN FACTURA V23 END === \*/','')

$block=@'

/* === PESTANA SIN FACTURA V23 START === */
.missing-tab-page{display:grid;gap:15px}
.missing-tab-header{display:flex;justify-content:space-between;align-items:center;padding:22px 24px}
.missing-tab-kicker{display:block;font-size:8px;letter-spacing:.12em;font-weight:850;color:#a06c18}
.missing-tab-header h2{font-size:22px;margin:6px 0}.missing-tab-header p{margin:0;color:#78877f;font-size:9px}
.missing-tab-count{text-align:right;background:#fff7e7;border:1px solid #efd7a0;border-radius:11px;padding:12px 16px;min-width:150px}
.missing-tab-count b{display:block;font-size:24px;color:#b97a17}.missing-tab-count span{display:block;margin-top:3px;font-size:8px;color:#8d7652}
.missing-list-panel{overflow:hidden}
.missing-list-head{display:grid;grid-template-columns:120px 180px minmax(250px,1.5fr) 150px 130px 120px 220px;gap:10px;padding:11px 14px;background:#f8faf9;border-bottom:1px solid var(--line);font-size:7px;text-transform:uppercase;letter-spacing:.05em;font-weight:850;color:#74837b}
.missing-list-body{max-height:calc(100vh - 300px);overflow:auto}
.missing-list-row{display:grid;grid-template-columns:120px 180px minmax(250px,1.5fr) 150px 130px 120px 220px;gap:10px;align-items:center;padding:12px 14px;border-bottom:1px solid #edf1ee;background:white}
.missing-list-row:hover{background:#fbfcfb}
.missing-list-row.removed{opacity:.68;background:#f7f8f7}
.missing-list-row b,.missing-list-row small{display:block}.missing-list-row b{font-size:9px;color:#283b31}.missing-list-row small{font-size:7px;color:#89958f;margin-top:3px}
.missing-state{display:inline-flex;padding:5px 7px;border-radius:20px;font-size:7px;font-weight:850;white-space:nowrap}
.missing-state.inactive{background:#fff0d2;color:#a66a0f}.missing-state.removed{background:#edf0ee;color:#717d77}
.missing-list-actions{display:flex;gap:6px;justify-content:flex-end}
.missing-list-actions button{height:31px;border-radius:7px;padding:0 9px;font-size:7px;font-weight:800;cursor:pointer}
.missing-list-actions .danger-btn{background:white;border:1px solid #ebc8c1;color:#b54d3d}.missing-list-actions .ok-btn{background:#e9f6ef;border:1px solid #cae4d6;color:#18724e}
.missing-list-empty{padding:35px;text-align:center;color:#87938d;font-size:10px}
@media(max-width:1200px){.missing-list-panel{overflow:auto}.missing-list-head,.missing-list-row{min-width:1120px}}
@media(max-width:700px){.missing-tab-header{align-items:flex-start;gap:15px}.missing-tab-count{min-width:115px}}
/* === PESTANA SIN FACTURA V23 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if(($check -match 'tab==="missing"') -and ($check -match '<span>Sin factura</span>') -and ($check -match 'missing-list-row')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V23 APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora los medidores sin factura tienen su propia pestaña." -ForegroundColor Green
  Write-Host "Se muestran como lista y no se mezclan con Facturas." -ForegroundColor Green
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
}else{throw "La verificacion final fallo."}

Read-Host "ENTER para cerrar"
