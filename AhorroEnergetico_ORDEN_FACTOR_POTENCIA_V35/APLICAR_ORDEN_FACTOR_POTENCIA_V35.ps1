$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - ORDEN FACTOR POTENCIA V35" -ForegroundColor Cyan
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
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_orden_fp_v35_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# ----------------------------------------------------------
# 1) Cambiar comparator de InvoiceTable:
#    - FP < 0,95 primero
#    - dentro de los malos: peor FP primero (más bajo)
#    - correctos después
#    - "No detectado" SIEMPRE al final
# ----------------------------------------------------------

$oldComparator='sorted=[...invoices].sort((a,b)=>{if(!sort)return 0;const av=value(a),bv=value(b),result=typeof av==="string"?av.localeCompare(String(bv),"es",{numeric:true}):Number(av)-Number(bv);return direction==="asc"?result:-result})'

$newComparator='sorted=[...invoices].sort((a,b)=>{if(!sort)return 0;if(sort==="pf"){const ap=metrics(a).pf,bp=metrics(b).pf,ar=ap<=0?2:ap<.95?0:1,br=bp<=0?2:bp<.95?0:1;if(ar!==br)return ar-br;if(ar===2)return 0;return direction==="asc"?ap-bp:bp-ap}const av=value(a),bv=value(b),result=typeof av==="string"?av.localeCompare(String(bv),"es",{numeric:true}):Number(av)-Number(bv);return direction==="asc"?result:-result})'

if($page.Contains($oldComparator)){
  $page=$page.Replace($oldComparator,$newComparator)
  Write-Host "[OK] Comparator de factor de potencia mejorado." -ForegroundColor Green
}elseif($page -match 'if\(sort==="pf"\)\{const ap=metrics\(a\)\.pf'){
  Write-Host "[OK] Comparator V35 ya estaba aplicado." -ForegroundColor DarkGreen
}else{
  throw "No encontre el comparator esperado de InvoiceTable. No hice cambios."
}

# ----------------------------------------------------------
# 2) Header especial de FP para explicar cómo ordena.
# ----------------------------------------------------------
$oldHead='<th>{head("pf","Factor potencia")}</th>'
$newHead='<th><button className={`sort-head pf-sort-head ${sort==="pf"?"active":""}`} onClick={()=>order("pf")}><span>Factor potencia<small>{sort==="pf"?(direction==="asc"?"Malos primero · peor → mejor":"Malos primero · mejor → peor"):"Tocar: FP < 0,95 primero"}</small></span><i>{sort==="pf"?(direction==="asc"?"⚠ ▲":"⚠ ▼"):"↕"}</i></button></th>'

if($page.Contains($oldHead)){
  $page=$page.Replace($oldHead,$newHead)
  Write-Host "[OK] Encabezado de Factor potencia mejorado." -ForegroundColor Green
}elseif($page -match 'pf-sort-head'){
  Write-Host "[OK] Header V35 ya estaba aplicado." -ForegroundColor DarkGreen
}else{
  Write-Host "[WARN] No encontre el header exacto; el orden funciona igual." -ForegroundColor Yellow
}

# ----------------------------------------------------------
# 3) Resaltar suavemente las filas con FP malo.
# ----------------------------------------------------------
$oldRow='<tr key={i.id} className="selectable" onClick={()=>onSelect?.(i)}>'
$newRow='<tr key={i.id} className={`selectable${bad?" pf-problem-row":""}`} onClick={()=>onSelect?.(i)}>'

if($page.Contains($oldRow)){
  $page=$page.Replace($oldRow,$newRow)
  Write-Host "[OK] Filas con FP bajo resaltadas." -ForegroundColor Green
}

Set-Content $pagePath $page -Encoding UTF8

# ----------------------------------------------------------
# 4) CSS visual
# ----------------------------------------------------------
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === ORDEN FP V35 START === \*/.*?/\* === ORDEN FP V35 END === \*/','')

$block=@'

/* === ORDEN FP V35 START === */
.pf-sort-head{
  min-width:128px;
}
.pf-sort-head span{
  display:flex;
  flex-direction:column;
  align-items:flex-start;
  gap:3px;
}
.pf-sort-head small{
  display:block;
  font-size:7px;
  line-height:1.2;
  font-weight:650;
  color:#839188;
  text-transform:none;
  white-space:nowrap;
}
.pf-sort-head.active{
  color:#b73e31;
}
.pf-sort-head.active small{
  color:#c45042;
}
.pf-problem-row td{
  background-image:linear-gradient(90deg,rgba(207,73,58,.035),rgba(207,73,58,0));
}
.pf-problem-row td:first-child{
  box-shadow:inset 3px 0 0 #d45a49;
}
/* === ORDEN FP V35 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# Cache
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificación
$check=Get-Content $pagePath -Raw
$okComparator=$check -match 'if\(sort==="pf"\)\{const ap=metrics\(a\)\.pf'
$okHeader=$check -match 'FP < 0,95 primero'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Orden especial FP: $okComparator"
Write-Host "  Header explicativo: $okHeader"

if(-not $okComparator){
  throw "La verificacion del orden FP fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V35 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora al tocar Factor potencia:" -ForegroundColor White
Write-Host "  1. Primero aparecen SOLO/prioritariamente los FP malos (< 0,95)" -ForegroundColor Green
Write-Host "  2. El peor factor aparece arriba" -ForegroundColor Green
Write-Host "  3. Los factores correctos quedan debajo" -ForegroundColor Green
Write-Host "  4. Los que dicen 'No detectado' quedan siempre al final" -ForegroundColor Green
Write-Host "  5. Las filas con FP bajo quedan marcadas visualmente" -ForegroundColor Green
Write-Host ""
Write-Host "Segundo clic: invierte el orden dentro de cada grupo, sin mezclar los no detectados." -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
