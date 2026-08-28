$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - SUBPESTANAS EN FACTURAS V24" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_facturas_subpestanas_v24_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# ----------------------------------------------------------
# 1) Sacar "missing" del tab principal y de la sidebar.
# ----------------------------------------------------------
$page=$page.Replace(
  'useState<"dashboard"|"invoices"|"missing"|"framing"|"tariffs"|"map"|"ai">',
  'useState<"dashboard"|"invoices"|"framing"|"tariffs"|"map"|"ai">'
)
$page=$page.Replace(
  'useState<"dashboard"|"invoices"|"missing"|"framing"|"tariffs"|"map">',
  'useState<"dashboard"|"invoices"|"framing"|"tariffs"|"map">'
)

# elimina boton sidebar "Sin factura"
$page=[regex]::Replace(
  $page,
  '(?s)<button className=\{tab==="missing"\?"active":""\} onClick=\{\(\)=>setTab\("missing"\)\}>.*?<span>Sin factura</span></button>',
  ''
)

# ----------------------------------------------------------
# 2) Eliminar vista principal tab==="missing" si existe.
# ----------------------------------------------------------
$missingStart=$page.IndexOf('{tab==="missing"&&')
$invoicesStart=$page.IndexOf('{tab==="invoices"&&')
if($missingStart -ge 0 -and $invoicesStart -gt $missingStart){
  $page=$page.Substring(0,$missingStart)+$page.Substring($invoicesStart)
  Write-Host "[OK] Vista independiente Sin factura eliminada." -ForegroundColor Green
}

# ----------------------------------------------------------
# 3) Estado para subpestañas dentro de Facturas.
# ----------------------------------------------------------
if($page -notmatch '\[invoiceSubTab,setInvoiceSubTab\]'){
  $anchor='const fileRef=useRef<HTMLInputElement>(null);'
  if($page.Contains($anchor)){
    $state='const[invoiceSubTab,setInvoiceSubTab]=useState<"received"|"missing">("received");'+"`r`n  "
    $page=$page.Replace($anchor,$state+$anchor)
  }else{
    throw "No encontre fileRef para agregar invoiceSubTab."
  }
}

# ----------------------------------------------------------
# 4) Reconstruir SOLO el bloque Facturas.
#    Conserva todo el contenido actual de Facturas como subpestaña "Con factura".
# ----------------------------------------------------------
$startMarker='{tab==="invoices"&&<>'
$nextCandidates=@(
  '{tab==="framing"&&',
  '{tab==="tariffs"&&',
  '{tab==="map"&&',
  '{tab==="ai"&&'
)

$start=$page.IndexOf($startMarker)
if($start -lt 0){throw "No encontre el inicio de la vista Facturas."}

$next=-1
foreach($candidate in $nextCandidates){
  $p=$page.IndexOf($candidate,$start+1)
  if($p -ge 0 -and ($next -lt 0 -or $p -lt $next)){$next=$p}
}
if($next -lt 0){throw "No encontre el final de la vista Facturas."}

$block=$page.Substring($start,$next-$start)
$openLen=$startMarker.Length
$inner=$block.Substring($openLen)

# quitar el cierre final </>} del bloque de facturas, usando el ultimo.
$closePos=$inner.LastIndexOf('</>}')
if($closePos -lt 0){throw "No encontre cierre </>} de Facturas."}
$inner=$inner.Substring(0,$closePos)

$missingView=@'
  {invoiceSubTab==="missing"&&<div className="invoice-missing-subpage">
    <section className="panel invoice-missing-summary">
      <div>
        <span>MEDIDORES SIN FACTURA</span>
        <h2>Seguimiento separado</h2>
        <p>Acá se muestran únicamente los medidores que no tienen facturación reciente o están en posible baja.</p>
      </div>
      <div className="invoice-missing-total">
        <b>{lifecycleMeters.length}</b>
        <small>medidores en seguimiento</small>
      </div>
    </section>

    <section className="panel invoice-missing-list-panel">
      <div className="invoice-missing-list-head">
        <span>Estado</span>
        <span>Medidor / ID</span>
        <span>Servicio</span>
        <span>Suministro</span>
        <span>Última factura</span>
        <span>Meses sin factura</span>
        <span>Acciones</span>
      </div>

      <div className="invoice-missing-list-body">
        {lifecycleMeters.map(m=>{
          const months=monthsBetween(m.last_seen_period,periods[0]||"");
          return <div className={`invoice-missing-list-row ${m.status==="removed"?"removed":"watch"}`} key={m.id}>
            <div><span className={`invoice-missing-state ${m.status||"inactive"}`}>{m.status==="removed"?"BAJA CONFIRMADA":"POSIBLE BAJA"}</span></div>
            <div><b>Medidor {m.meter_number||"S/D"}</b><small>{m.tracking_code||"Sin ID"}</small></div>
            <div><b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b><small>{m.sites?.address||"Sin dirección registrada"}</small></div>
            <div><b>{m.supply_number||"S/D"}</b><small>{m.current_tariff_code||"Sin tarifa"}</small></div>
            <div><b>{m.last_seen_period?.slice(0,7)||"S/D"}</b><small>último período cargado</small></div>
            <div><b>{months}</b><small>meses</small></div>
            <div className="invoice-missing-list-actions">
              {m.status!=="removed"&&<button className="danger-btn" onClick={()=>updateMeterStatus(m.id,"removed")}>Confirmar baja</button>}
              <button className="ok-btn" onClick={()=>updateMeterStatus(m.id,"active")}>Continúa activo</button>
            </div>
          </div>
        })}
        {!lifecycleMeters.length&&<div className="invoice-missing-list-empty">No hay medidores sin facturación reciente.</div>}
      </div>
    </section>
  </div>}
'@

$newBlock = @"
{tab==="invoices"&&<>
  <div className="invoice-subtabs">
    <button className={invoiceSubTab==="received"?"active":""} onClick={()=>setInvoiceSubTab("received")}>
      <span>Facturas recibidas</span>
      <b>{dashboardReceived}</b>
    </button>
    <button className={invoiceSubTab==="missing"?"active missing":""} onClick={()=>setInvoiceSubTab("missing")}>
      <span>Sin factura</span>
      <b>{lifecycleMeters.length}</b>
    </button>
  </div>

  {invoiceSubTab==="received"&&<>
$inner
  </>}

$missingView
</>}
"@

$page=$page.Substring(0,$start)+$newBlock+$page.Substring($next)
Set-Content $pagePath $page -Encoding UTF8

Write-Host "[OK] Sin factura movido dentro de Facturas como subpestaña." -ForegroundColor Green

# ----------------------------------------------------------
# 5) CSS
# ----------------------------------------------------------
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === FACTURAS SUBPESTANAS V24 START === \*/.*?/\* === FACTURAS SUBPESTANAS V24 END === \*/','')

$cssBlock=@'

/* === FACTURAS SUBPESTANAS V24 START === */
.invoice-subtabs{
  display:flex;
  gap:8px;
  margin:0 0 14px;
  padding:5px;
  width:max-content;
  max-width:100%;
  border:1px solid #dbe5df;
  border-radius:11px;
  background:#f7faf8;
}
.invoice-subtabs button{
  display:flex;
  align-items:center;
  gap:10px;
  min-height:39px;
  padding:0 14px;
  border:0;
  border-radius:8px;
  background:transparent;
  color:#61736a;
  font-size:9px;
  font-weight:800;
  cursor:pointer;
}
.invoice-subtabs button b{
  display:grid;
  place-items:center;
  min-width:24px;
  height:24px;
  padding:0 6px;
  border-radius:20px;
  background:#e7eeea;
  color:#52665b;
  font-size:8px;
}
.invoice-subtabs button.active{
  background:#188b5b;
  color:white;
  box-shadow:0 4px 12px rgba(24,139,91,.16);
}
.invoice-subtabs button.active b{
  background:#ffffff25;
  color:white;
}
.invoice-subtabs button.missing:not(.active) b{
  background:#fff0ed;
  color:#c94c39;
}

.invoice-missing-subpage{display:grid;gap:14px}
.invoice-missing-summary{
  display:flex;
  justify-content:space-between;
  align-items:center;
  padding:20px 22px;
}
.invoice-missing-summary>div:first-child>span{
  display:block;
  font-size:8px;
  letter-spacing:.1em;
  font-weight:850;
  color:#a06c18;
}
.invoice-missing-summary h2{margin:5px 0;font-size:20px}
.invoice-missing-summary p{margin:0;color:#7a8981;font-size:9px}
.invoice-missing-total{
  min-width:150px;
  text-align:right;
  padding:10px 13px;
  border-radius:10px;
  background:#fff6e7;
  border:1px solid #efd7a2;
}
.invoice-missing-total b{display:block;font-size:23px;color:#b47717}
.invoice-missing-total small{display:block;margin-top:3px;color:#8d7652;font-size:8px}

.invoice-missing-list-panel{overflow:hidden}
.invoice-missing-list-head,
.invoice-missing-list-row{
  display:grid;
  grid-template-columns:120px 180px minmax(250px,1.5fr) 150px 130px 120px 220px;
  gap:10px;
}
.invoice-missing-list-head{
  padding:11px 14px;
  background:#f8faf9;
  border-bottom:1px solid var(--line);
  font-size:7px;
  text-transform:uppercase;
  letter-spacing:.05em;
  font-weight:850;
  color:#74837b;
}
.invoice-missing-list-body{
  max-height:calc(100vh - 330px);
  overflow:auto;
}
.invoice-missing-list-row{
  align-items:center;
  padding:12px 14px;
  border-bottom:1px solid #edf1ee;
  background:white;
}
.invoice-missing-list-row:hover{background:#fbfcfb}
.invoice-missing-list-row.removed{opacity:.68;background:#f7f8f7}
.invoice-missing-list-row b,.invoice-missing-list-row small{display:block}
.invoice-missing-list-row b{font-size:9px;color:#283b31}
.invoice-missing-list-row small{font-size:7px;color:#89958f;margin-top:3px}
.invoice-missing-state{
  display:inline-flex;
  padding:5px 7px;
  border-radius:20px;
  font-size:7px;
  font-weight:850;
  white-space:nowrap;
}
.invoice-missing-state.inactive{background:#fff0d2;color:#a66a0f}
.invoice-missing-state.removed{background:#edf0ee;color:#717d77}
.invoice-missing-list-actions{display:flex;gap:6px;justify-content:flex-end}
.invoice-missing-list-actions button{
  height:31px;
  border-radius:7px;
  padding:0 9px;
  font-size:7px;
  font-weight:800;
  cursor:pointer;
}
.invoice-missing-list-actions .danger-btn{background:white;border:1px solid #ebc8c1;color:#b54d3d}
.invoice-missing-list-actions .ok-btn{background:#e9f6ef;border:1px solid #cae4d6;color:#18724e}
.invoice-missing-list-empty{padding:35px;text-align:center;color:#87938d;font-size:10px}
@media(max-width:1200px){
  .invoice-missing-list-panel{overflow:auto}
  .invoice-missing-list-head,.invoice-missing-list-row{min-width:1120px}
}
/* === FACTURAS SUBPESTANAS V24 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$cssBlock+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
$okNoSidebar=$check -notmatch '<span>Sin factura</span></button>.*?</nav>'
$okSubtabs=$check -match 'invoice-subtabs'
$okMissingInside=$check -match 'invoiceSubTab==="missing"'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Subpestañas Facturas: $okSubtabs"
Write-Host "  Sin factura dentro:   $okMissingInside"

if(-not ($okSubtabs -and $okMissingInside)){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V24 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora Facturas tiene dos subpestanas:" -ForegroundColor White
Write-Host " - Facturas recibidas" -ForegroundColor Green
Write-Host " - Sin factura" -ForegroundColor Green
Write-Host ""
Write-Host "Sin factura ya NO aparece en la sidebar." -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
