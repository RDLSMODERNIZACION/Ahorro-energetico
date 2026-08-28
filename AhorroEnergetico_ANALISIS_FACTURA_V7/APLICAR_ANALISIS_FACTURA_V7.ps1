$ErrorActionPreference="Stop"
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - ANALISIS INDIVIDUAL FACTURA V7" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$front=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))){$front=$c;break}
}
if(-not $front){throw "No encontre la carpeta front."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"
$componentTarget=Join-Path $front "app\invoice-analysis-panel.tsx"
$componentSource=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "invoice-analysis-panel.tsx"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_analisis_factura_v7_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force
if(Test-Path $componentTarget){Copy-Item $componentTarget (Join-Path $backup "invoice-analysis-panel.tsx") -Force}

Copy-Item $componentSource $componentTarget -Force
Write-Host "[OK] Componente de analisis instalado." -ForegroundColor Green

$page=Get-Content $pagePath -Raw

if($page -notmatch 'invoice-analysis-panel'){
  $anchor='import { HistoricalAnalysis } from "./analysis-charts";'
  if($page.Contains($anchor)){
    $page=$page.Replace($anchor,$anchor+"`r`n"+'import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";')
  }else{
    $page='"use client";'+ "`r`n" +'import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";'+ "`r`n" + ($page -replace '^\s*﻿?"use client";\s*','')
  }
  Write-Host "[OK] Import agregado a page.tsx." -ForegroundColor Green
}

# Reemplaza todas las aperturas laterales por el analisis completo.
$pattern='\{selectedInvoice&&<MeterDetail\s+invoice=\{selectedInvoice\}\s+history=\{invoices\.filter\(x=>x\.meter_id===selectedInvoice\.meter_id\)\}\s+onClose=\{\(\)=>setSelectedInvoice\(null\)\}\s*/>\}'
$replacement='{selectedInvoice&&<InvoiceAnalysisPanel invoice={selectedInvoice} history={invoices.filter(x=>x.meter_id===selectedInvoice.meter_id)} tariffSavings={tariffSavings} onClose={()=>setSelectedInvoice(null)}/>}'

$count=[regex]::Matches($page,$pattern).Count
if($count -gt 0){
  $page=[regex]::Replace($page,$pattern,$replacement)
  Write-Host "[OK] Reemplace $count panel(es) lateral(es) por el analisis completo." -ForegroundColor Green
}elseif($page -match 'selectedInvoice&&<InvoiceAnalysisPanel'){
  Write-Host "[OK] El analisis completo ya estaba aplicado." -ForegroundColor DarkGreen
}else{
  # Fallback flexible.
  $fallback='(?s)\{selectedInvoice&&<MeterDetail\b.*?onClose=\{\(\)=>setSelectedInvoice\(null\)\}\s*/>\}'
  $count2=[regex]::Matches($page,$fallback).Count
  if($count2 -gt 0){
    $page=[regex]::Replace($page,$fallback,$replacement)
    Write-Host "[OK] Reemplace $count2 panel(es) usando deteccion flexible." -ForegroundColor Green
  }else{
    throw "No encontre el bloque MeterDetail para reemplazar. No hice el cambio."
  }
}

Set-Content $pagePath $page -Encoding UTF8

$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === ANALISIS INDIVIDUAL FACTURA V7 START === \*/.*?/\* === ANALISIS INDIVIDUAL FACTURA V7 END === \*/','')
$cssSource=Get-Content (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "analisis-factura-v7.css") -Raw
$css=$css.TrimEnd()+"`r`n"+$cssSource+"`r`n"
Set-Content $cssPath $css -Encoding UTF8
Write-Host "[OK] Estilos agregados." -ForegroundColor Green

# Sacamos la marca roja de diagnóstico V6 para volver a una interfaz limpia.
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === DIAGNOSTICO V6 START === \*/.*?/\* === DIAGNOSTICO V6 END === \*/','')
Set-Content $cssPath $css -Encoding UTF8

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$page2=Get-Content $pagePath -Raw
if(($page2 -match 'InvoiceAnalysisPanel') -and (Test-Path $componentTarget)){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " ANALISIS INDIVIDUAL V7 APLICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora al tocar una factura se abre un panel completo con:" -ForegroundColor White
  Write-Host " - KPIs de esa factura" -ForegroundColor Green
  Write-Host " - Grafico historico 24 meses" -ForegroundColor Green
  Write-Host " - Consumo / importe / demanda / factor de potencia" -ForegroundColor Green
  Write-Host " - Potencia contratada vs demanda" -ForegroundColor Green
  Write-Host " - Ahorros de esa factura" -ForegroundColor Green
  Write-Host " - Conceptos facturados" -ForegroundColor Green
  Write-Host " - Mediciones registradas" -ForegroundColor Green
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Reinicia con: cd `"$front`"; npm run dev" -ForegroundColor Cyan
  Write-Host "Luego Ctrl+F5." -ForegroundColor Cyan
}else{throw "La verificacion final fallo."}

Read-Host "ENTER para cerrar"
