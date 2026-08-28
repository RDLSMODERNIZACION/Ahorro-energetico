$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - LIMPIAR RESUMEN V19" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_resumen_limpio_v19_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

# Elimina el bloque completo que contiene:
# - Estado del analisis
# - Alertas mensuales
# Está envuelto por <div className="dashboard-status"> ... </div>
$pattern='(?s)<div className="dashboard-status">.*?</div>(?=\s*<MeterLifecyclePanel|\s*</>|\s*\})'

if([regex]::IsMatch($page,$pattern)){
  $page=[regex]::Replace($page,$pattern,'',1)
  Write-Host "[OK] Quite Estado del analisis + Alertas mensuales del Resumen." -ForegroundColor Green
}else{
  # Fallback más acotado basado en títulos.
  $fallback='(?s)<div className="dashboard-status">.*?Estado del análisis.*?Alertas mensuales.*?</div>'
  if([regex]::IsMatch($page,$fallback)){
    $page=[regex]::Replace($page,$fallback,'',1)
    Write-Host "[OK] Bloque quitado usando deteccion por titulos." -ForegroundColor Green
  }elseif(($page -notmatch 'Estado del análisis') -and ($page -notmatch 'Alertas mensuales')){
    Write-Host "[OK] Esos bloques ya no estan en page.tsx." -ForegroundColor DarkGreen
  }else{
    throw "No pude identificar de forma segura el bloque dashboard-status."
  }
}

Set-Content $pagePath $page -Encoding UTF8

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
if(($check -notmatch 'Estado del análisis') -and ($check -notmatch 'Alertas mensuales')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V19 APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Se quitaron del Resumen:" -ForegroundColor White
  Write-Host " - Estado del analisis" -ForegroundColor Green
  Write-Host " - Alertas mensuales" -ForegroundColor Green
  Write-Host ""
  Write-Host "No se tocaron Facturas ni la seccion IA." -ForegroundColor White
  Write-Host ""
  Write-Host "Backup:" -ForegroundColor DarkGray
  Write-Host "  $backup" -ForegroundColor DarkGray
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
