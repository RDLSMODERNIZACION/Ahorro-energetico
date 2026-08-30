$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if (Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if (Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$path=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup="$path.bak-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

$bad='})():<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}:<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}'

$good='})():<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}'

if($text.Contains($bad)){
    $text=$text.Replace($bad,$good)
    Set-Content $path $text -Encoding UTF8
    Write-Host "OK - error de parseo V6 corregido." -ForegroundColor Green
    Write-Host "Backup: $backup"
} else {
    # Fallback: corregir sólo el patrón duplicado del cierre ternario.
    $pattern='\}\)\(\):<InvoiceTrend rows=\{sorted\} metric=\{metric\} selectedPeriod=\{periodOf\(selected\)\} onPeriod=\{setSelectedPeriod\}/>\}:<InvoiceTrend rows=\{sorted\} metric=\{metric\} selectedPeriod=\{periodOf\(selected\)\} onPeriod=\{setSelectedPeriod\}/>\}'
    $replacement='})():<InvoiceTrend rows={sorted} metric={metric} selectedPeriod={periodOf(selected)} onPeriod={setSelectedPeriod}/>}'
    $new=[regex]::Replace($text,$pattern,$replacement)
    if($new -eq $text){
        throw "No encontré el patrón roto de V6. Pasame las líneas 210-230 de invoice-analysis-panel.tsx."
    }
    Set-Content $path $new -Encoding UTF8
    Write-Host "OK - error de parseo V6 corregido con fallback." -ForegroundColor Green
    Write-Host "Backup: $backup"
}

Write-Host ""
Write-Host "Ahora ejecutá:" -ForegroundColor Yellow
Write-Host "  cd front"
Write-Host "  npm run dev"
