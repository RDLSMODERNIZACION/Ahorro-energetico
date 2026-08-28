$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - UBICACION ARRIBA DE CONCEPTOS V10" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$front=$null

foreach($c in $candidates){
  if((Test-Path (Join-Path $c "app\invoice-analysis-panel.tsx")) -and
     (Test-Path (Join-Path $c "app\meter-location-editor.tsx"))){
    $front=$c
    break
  }
}

if(-not $front){
  throw "No encontre front\app\invoice-analysis-panel.tsx y meter-location-editor.tsx. Primero aplica el V9."
}

$analysisPath=Join-Path $front "app\invoice-analysis-panel.tsx"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ubicacion_posicion_v10_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $analysisPath (Join-Path $backup "invoice-analysis-panel.tsx") -Force

$analysis=Get-Content $analysisPath -Raw

# Elimina cualquier instancia previa del editor para poder ubicarlo exactamente una sola vez.
$patternEditor='(?s)\s*<MeterLocationEditor\s+meterId=\{selected\.meter_id\}\s+label=\{`\$\{m\?\.service_name\|\|m\?\.sites\?\.name\|\|"Servicio"\}\s*·\s*Medidor\s*\$\{m\?\.meter_number\|\|"S/D"\}`\}\s*/>\s*'
$analysis=[regex]::Replace($analysis,$patternEditor,"`r`n")

# Fallback más flexible por si cambió el formato del label.
$analysis=[regex]::Replace(
  $analysis,
  '(?s)\s*<MeterLocationEditor\b[^>]*/>\s*',
  "`r`n"
)

$insert='<MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>'+"`r`n`r`n      "

# Inserta inmediatamente ANTES de la sección "Conceptos facturados".
$patternConcepts='(<section className="invoice-analysis-panel">\s*<h3>Conceptos facturados</h3>)'
if([regex]::IsMatch($analysis,$patternConcepts)){
  $analysis=[regex]::Replace($analysis,$patternConcepts,$insert+'$1',1)
  Write-Host "[OK] Ubicacion colocada exactamente arriba de Conceptos facturados." -ForegroundColor Green
}else{
  throw "No encontre la seccion Conceptos facturados."
}

Set-Content $analysisPath $analysis -Encoding UTF8

# Limpia cache Vite para que el cambio se vea.
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $analysisPath -Raw
$idxMap=$check.IndexOf("<MeterLocationEditor")
$idxConcepts=$check.IndexOf("<h3>Conceptos facturados</h3>")

if($idxMap -ge 0 -and $idxConcepts -gt $idxMap){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V10 APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "La seccion Ubicacion del medidor ahora queda:" -ForegroundColor White
  Write-Host "  Detalle completo / Oportunidades" -ForegroundColor DarkGray
  Write-Host "  UBICACION DEL MEDIDOR" -ForegroundColor Green
  Write-Host "  Conceptos facturados" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Reinicia:" -ForegroundColor Cyan
  Write-Host "  cd `"$front`"" -ForegroundColor White
  Write-Host "  npm run dev" -ForegroundColor White
  Write-Host "  Ctrl + F5" -ForegroundColor White
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
