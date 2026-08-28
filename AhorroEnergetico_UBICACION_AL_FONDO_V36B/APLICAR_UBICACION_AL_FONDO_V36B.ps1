$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - UBICACION AL FONDO V36B" -ForegroundColor Cyan
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
     (Test-Path (Join-Path $c "app\meter-location-editor.tsx"))){
    $front=$c
    break
  }
}
if(-not $front){
  throw "No encontre front\app\invoice-analysis-panel.tsx y meter-location-editor.tsx."
}

$analysisPath=Join-Path $front "app\invoice-analysis-panel.tsx"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ubicacion_fondo_v36b_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $analysisPath (Join-Path $backup "invoice-analysis-panel.tsx") -Force

$analysis=Get-Content $analysisPath -Raw

# 1) Verificar import.
if($analysis -notmatch 'import\s+\{\s*MeterLocationEditor\s*\}\s+from\s+"\.\/meter-location-editor";'){
  $anchor='import { useMemo, useState } from "react";'
  if($analysis.Contains($anchor)){
    $analysis=$analysis.Replace(
      $anchor,
      $anchor+"`r`n"+'import { MeterLocationEditor } from "./meter-location-editor";'
    )
  }else{
    throw "No encontre el import base de React para agregar MeterLocationEditor."
  }
}

# 2) Eliminar cualquier instancia previa del bloque de ubicación.
$analysis=[regex]::Replace(
  $analysis,
  '(?s)\s*<MeterLocationEditor\b[^>]*/>\s*',
  "`r`n"
)

# 3) Insertar UNA SOLA VEZ justo antes del cierre de invoice-analysis-page.
$location='<MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>'

# El componente termina con dos </div>: invoice-analysis-page + backdrop.
$rx=New-Object System.Text.RegularExpressions.Regex(
  '(\s*</div>\s*</div>\s*\}\s*)$',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if(-not $rx.IsMatch($analysis)){
  throw "No pude localizar el cierre final de InvoiceAnalysisPanel."
}

$analysis=$rx.Replace(
  $analysis,
  "`r`n      $location`r`n`$1",
  1
)

Set-Content $analysisPath $analysis -Encoding UTF8

# 4) Verificación real: una sola instancia y ubicada después de Mediciones registradas.
$check=Get-Content $analysisPath -Raw
$instances=([regex]::Matches($check,'<MeterLocationEditor\b')).Count
$locPos=$check.LastIndexOf('<MeterLocationEditor')
$measurePos=$check.LastIndexOf('Mediciones registradas')

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Instancias de ubicación: $instances"
Write-Host "  Posición después de Mediciones: $($locPos -gt $measurePos)"

if($instances -ne 1 -or $locPos -lt 0 -or $locPos -le $measurePos){
  throw "La ubicación no quedó una sola vez al final del análisis."
}

# Cache Vite
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V36B APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora la Ubicacion del medidor queda al final real del análisis:" -ForegroundColor Green
Write-Host "  - después de Conceptos facturados" -ForegroundColor Green
Write-Host "  - después de Mediciones registradas" -ForegroundColor Green
Write-Host "  - como último bloque de la ficha" -ForegroundColor Green
Write-Host ""
Write-Host "Este fix modifica invoice-analysis-panel.tsx directamente." -ForegroundColor Yellow
Write-Host "No depende de useEffect ni de page.tsx." -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
