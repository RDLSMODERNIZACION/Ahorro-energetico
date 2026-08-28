$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - COS FI EN ROJO V8" -ForegroundColor Cyan
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
  if((Test-Path (Join-Path $c "app\invoice-analysis-panel.tsx")) -and
     (Test-Path (Join-Path $c "app\globals.css"))){
    $front=$c
    break
  }
}

if(-not $front){
  throw "No encontre front\app\invoice-analysis-panel.tsx. Primero debe estar aplicado el V7."
}

$componentPath=Join-Path $front "app\invoice-analysis-panel.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_cosfi_rojo_v8_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $componentPath (Join-Path $backup "invoice-analysis-panel.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$component=Get-Content $componentPath -Raw

# 1) Marca cada barra de FP bajo con clase bad-pf.
$old='className={`invoice-analysis-bar${selectedPeriod===d.period?" selected":""}`}'
$new='className={`invoice-analysis-bar${metric==="pf"&&d.value>0&&d.value<.95?" bad-pf":""}${metric==="pf"&&d.value>=.95?" good-pf":""}${selectedPeriod===d.period?" selected":""}`}'
if($component.Contains($old)){
  $component=$component.Replace($old,$new)
  Write-Host "[OK] Barras con cos fi bajo identificadas." -ForegroundColor Green
}elseif($component -match 'bad-pf'){
  Write-Host "[OK] Clasificacion de cos fi ya estaba aplicada." -ForegroundColor DarkGreen
}else{
  throw "No encontre el bloque de barras esperado en InvoiceTrend."
}

# 2) Agrega linea limite 0.95 en el grafico de factor de potencia.
$anchor='{metric==="demand"&&data.map((d,index)=>d.contracted>0?<line key={`c-${d.period}`} className="invoice-contract-line"'
if($component.Contains($anchor) -and $component -notmatch 'invoice-pf-limit'){
  $insert='{metric==="pf"&&<g className="invoice-pf-limit"><line x1={left} x2={width-right} y1={top+plotH-(0.95/max)*plotH} y2={top+plotH-(0.95/max)*plotH}/><text x={width-right-4} y={top+plotH-(0.95/max)*plotH-7} textAnchor="end">Límite cos φ 0,95</text></g>}'
  $component=$component.Replace($anchor,$insert+$anchor)
  Write-Host "[OK] Linea limite cos fi 0,95 agregada." -ForegroundColor Green
}

# 3) Agrega leyenda debajo del grafico.
$chartClose='</svg></div>'
if($component.Contains($chartClose) -and $component -notmatch 'invoice-pf-legend'){
  $replacement='</svg>{metric==="pf"&&<div className="invoice-pf-legend"><span><i className="good"/>Correcto: cos φ ≥ 0,95</span><span><i className="bad"/>Revisar: cos φ &lt; 0,95</span></div>}</div>'
  $component=$component.Replace($chartClose,$replacement)
  Write-Host "[OK] Leyenda de cos fi agregada." -ForegroundColor Green
}

Set-Content $componentPath $component -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === COSFI ROJO V8 START === \*/.*?/\* === COSFI ROJO V8 END === \*/','')

$block=@'

/* === COSFI ROJO V8 START === */

/* En modo Factor de potencia:
   verde = correcto
   rojo = cos phi menor a 0,95
*/
.invoice-analysis-bar.good-pf rect{
  fill:#219565 !important;
}

.invoice-analysis-bar.bad-pf rect{
  fill:#d84c3f !important;
}

.invoice-analysis-bar.bad-pf:hover rect{
  fill:#b6342b !important;
}

.invoice-analysis-bar.bad-pf.selected rect{
  fill:#a82821 !important;
  stroke:#701b17;
  stroke-width:2;
}

.invoice-analysis-bar.good-pf.selected rect{
  fill:#116943 !important;
  stroke:#0b4f32;
  stroke-width:2;
}

/* Limite reglado visualmente en 0,95 */
.invoice-pf-limit line{
  stroke:#c23b31 !important;
  stroke-width:2 !important;
  stroke-dasharray:7 5;
}

.invoice-pf-limit text{
  fill:#b62f27 !important;
  font-size:10px !important;
  font-weight:800;
}

.invoice-pf-legend{
  display:flex;
  justify-content:flex-end;
  gap:18px;
  padding:0 18px 14px;
  color:#687971;
  font-size:9px;
  font-weight:700;
}

.invoice-pf-legend span{
  display:flex;
  align-items:center;
  gap:6px;
}

.invoice-pf-legend i{
  width:11px;
  height:11px;
  border-radius:3px;
  display:inline-block;
}

.invoice-pf-legend i.good{
  background:#219565;
}

.invoice-pf-legend i.bad{
  background:#d84c3f;
}

/* === COSFI ROJO V8 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# Limpia cache Vite
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $componentPath -Raw
if(($check -match 'bad-pf') -and ($check -match 'invoice-pf-limit')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " COS FI EN ROJO V8 APLICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "En el grafico Factor potencia:" -ForegroundColor White
  Write-Host " - Verde: cos fi >= 0,95" -ForegroundColor Green
  Write-Host " - Rojo:  cos fi < 0,95" -ForegroundColor Red
  Write-Host " - Linea roja punteada: limite 0,95" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Reinicia:" -ForegroundColor Cyan
  Write-Host "  cd `"$front`"" -ForegroundColor White
  Write-Host "  npm run dev" -ForegroundColor White
  Write-Host "  Ctrl + F5" -ForegroundColor White
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
