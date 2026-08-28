$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - ALERTAS CLICK AL MEDIDOR V17" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_ia_alertas_click_v17_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# Agrega helper para abrir por meter_id cuando la alerta no tenga invoice directo.
if($page -notmatch 'const openMeterById='){
  $anchor='const openMeter=(i:Invoice)=>{setSelectedInvoice(i);setSelectedMeter(i.meter_id)};'
  if($page.Contains($anchor)){
    $helper=$anchor+"`r`n  "+'const openMeterById=(meterId?:string)=>{if(!meterId)return;const i=[...invoices].filter(x=>x.meter_id===meterId).sort((a,b)=>invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];if(i)openMeter(i)};'
    $page=$page.Replace($anchor,$helper)
  }else{throw "No encontre openMeter."}
}

# En alertas faltantes, guardar meterId.
$page=$page.Replace(
  'critical.push({kind:"missing",score:60,label:m.service_name||m.meter_number||"Medidor",detail:`Factura faltante en ${controlPeriod||latest}`,invoice:null});',
  'critical.push({kind:"missing",score:60,label:m.service_name||m.meter_number||"Medidor",detail:`Factura faltante en ${controlPeriod||latest}`,invoice:null,meterId:m.id});'
)

# En todas las alertas/opportunities/changes, agregar meterId si no existe.
$page=[regex]::Replace($page,
  'critical\.push\(\{kind:"pf",score:\(\.95-x\.pf\)\*100,label:m\?\.service_name\|\|m\?\.meter_number\|\|"Medidor",detail:`([^`]+)`,invoice:i\}\);',
  'critical.push({kind:"pf",score:(.95-x.pf)*100,label:m?.service_name||m?.meter_number||"Medidor",detail:`$1`,invoice:i,meterId:i.meter_id});'
)
$page=$page.Replace('invoice:i});','invoice:i,meterId:i.meter_id});')

# Reemplaza onClick para usar invoice o meterId.
$page=$page.Replace(
  'onClick={()=>a.invoice&&openMeter(a.invoice)}',
  'onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}'
)

# Agrega title/indicacion de clic.
$page=$page.Replace(
  '<button key={`${a.kind}-${index}`} onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>',
  '<button key={`${a.kind}-${index}`} className="ai-alert-clickable" title="Abrir análisis del medidor" onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>'
)
$page=$page.Replace(
  '<button key={index} onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>',
  '<button key={index} className="ai-alert-clickable" title="Abrir análisis del medidor" onClick={()=>a.invoice?openMeter(a.invoice):openMeterById(a.meterId)}>'
)

Set-Content $pagePath $page -Encoding UTF8

$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === ALERTAS CLICK V17 START === \*/.*?/\* === ALERTAS CLICK V17 END === \*/','')

$block=@'

/* === ALERTAS CLICK V17 START === */
.ai-alert-clickable{
  cursor:pointer !important;
  position:relative;
}
.ai-alert-clickable:after{
  content:"›";
  position:absolute;
  right:8px;
  top:50%;
  transform:translateY(-50%);
  font-size:18px;
  color:#93a39b;
  opacity:0;
  transition:.15s;
}
.ai-alert-clickable:hover{
  background:#f4faf6 !important;
  box-shadow:inset 3px 0 0 #188b5b;
}
.ai-alert-clickable:hover:after{opacity:1}
.ai-alert-clickable em{
  margin-right:12px;
}
/* === ALERTAS CLICK V17 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if(($check -match 'openMeterById') -and ($check -match 'ai-alert-clickable')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V17 APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora podes hacer clic en:" -ForegroundColor White
  Write-Host " - Alertas criticas" -ForegroundColor Green
  Write-Host " - Top oportunidades" -ForegroundColor Green
  Write-Host " - Que cambio este mes" -ForegroundColor Green
  Write-Host ""
  Write-Host "Y abre directamente el analisis individual del medidor." -ForegroundColor Green
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
}else{throw "La verificacion final fallo."}

Read-Host "ENTER para cerrar"
