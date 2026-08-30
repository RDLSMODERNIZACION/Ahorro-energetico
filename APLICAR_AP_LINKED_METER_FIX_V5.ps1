$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$dstBack = Join-Path $repo "back\app\routers\public_lighting.py"
$dstFront = Join-Path $repo "front\app\public-lighting-panel.tsx"

$srcBack = Join-Path $scriptDir "payload\back\app\routers\public_lighting.py"
$srcFront = Join-Path $scriptDir "payload\front\app\public-lighting-panel.tsx"

foreach($f in @($dstBack,$dstFront,$srcBack,$srcFront)){
  if(-not (Test-Path $f)){
    throw "No encontré: $f"
  }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $dstBack "$dstBack.bak-$stamp" -Force
Copy-Item $dstFront "$dstFront.bak-$stamp" -Force

Copy-Item $srcBack $dstBack -Force
Copy-Item $srcFront $dstFront -Force

Write-Host ""
Write-Host "AP LINKED METER FIX V5 aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Corregido:" -ForegroundColor Cyan
Write-Host "  public_lighting_meters.linked_meter_id -> meters.id"
Write-Host "  AP usa invoices / invoice_measurements / invoice_lines generales"
Write-Host "  Análisis individual AP usa InvoiceAnalysisPanel"
Write-Host "  Volver a Alumbrado Público"
Write-Host "  Demanda / Importe / Factor de potencia / Tarifaria"
Write-Host ""
Write-Host "No requiere ejecutar SQL adicional." -ForegroundColor Green
Write-Host "La base ya fue migrada."
Write-Host ""
Write-Host "Reiniciá backend y frontend para probar." -ForegroundColor Yellow
