$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - IA AHORRO DEL MES V34" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_ia_ahorro_mes_v34_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw
$before=$page

# ------------------------------------------------------------
# CORRECCION:
# En IA se estaba usando tariffAnnual, que puede sumar una base distinta.
# Debe usar EXACTAMENTE el mismo cálculo del Resumen:
# dashboardTotalMonthly * 12
# y mostrar el mes correspondiente.
# ------------------------------------------------------------

# Reemplazo exacto más común
$page=$page.Replace(
  '<article className="green"><span>Ahorro anual potencial</span><b>{money.format(tariffAnnual)}</b><small>estimación actual</small></article>',
  '<article className="green"><span>Ahorro anual potencial</span><b>{money.format(dashboardTotalMonthly*12)}</b><small>{dashboardPeriodLabel} · mensual {money.format(dashboardTotalMonthly)}</small></article>'
)

# Variantes por textos/cambios anteriores
$page=[regex]::Replace(
  $page,
  '<article className="green">\s*<span>Ahorro anual potencial</span>\s*<b>\{money\.format\((?:tariffAnnual|annualSaving)\)\}</b>\s*<small>.*?</small>\s*</article>',
  '<article className="green"><span>Ahorro anual potencial</span><b>{money.format(dashboardTotalMonthly*12)}</b><small>{dashboardPeriodLabel} · mensual {money.format(dashboardTotalMonthly)}</small></article>',
  1
)

# Si existe KPI similar sin article green
$page=[regex]::Replace(
  $page,
  '(<span>Ahorro anual potencial</span>\s*<b>)\{money\.format\((?:tariffAnnual|annualSaving)\)\}(</b>\s*<small>)[^<]*(</small>)',
  '$1{money.format(dashboardTotalMonthly*12)}$2{dashboardPeriodLabel} · mensual {money.format(dashboardTotalMonthly)}$3',
  1
)

# También actualizar el texto de resumen de IA si el valor se menciona de forma estática en tarjetas.
$page=$page.Replace(
  'Ahorro anual potencial</span><b>{money.format(tariffAnnual)}</b>',
  'Ahorro anual potencial</span><b>{money.format(dashboardTotalMonthly*12)}</b>'
)

Set-Content $pagePath $page -Encoding UTF8

# CSS opcional para el mes más visible
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === IA AHORRO MES V34 START === \*/.*?/\* === IA AHORRO MES V34 END === \*/','')
$block=@'

/* === IA AHORRO MES V34 START === */
.ai-alert-grid .green small{
  font-weight:700;
  color:#6b8f7d;
}
/* === IA AHORRO MES V34 END === */
'@
$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# Limpiar cache Vite
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
$ok=$check -match 'Ahorro anual potencial</span><b>\{money\.format\(dashboardTotalMonthly\*12\)\}</b>'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  IA usa ahorro del mismo mes que Resumen: $ok"

if(-not $ok){
  Write-Host "[ERROR] No encontre la tarjeta de IA esperada." -ForegroundColor Red
  Write-Host "No hice reemplazos destructivos." -ForegroundColor Yellow
  Write-Host "Backup: $backup" -ForegroundColor Yellow
  Read-Host "ENTER para cerrar"
  exit 1
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V34 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora IA y Resumen usan exactamente:" -ForegroundColor White
Write-Host "  ahorro mensual del ultimo periodo * 12" -ForegroundColor Green
Write-Host ""
Write-Host "La tarjeta IA tambien muestra el mes y el valor mensual." -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
