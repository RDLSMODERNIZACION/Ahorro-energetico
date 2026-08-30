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
$backup="$path.bak-v20-metric-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

$start=$text.IndexOf('function TariffSavingTrend(')
$end=$text.IndexOf('function InvoiceTrend(',$start)

if($start -lt 0 -or $end -lt 0){
    throw "No encontré TariffSavingTrend/InvoiceTrend."
}

$block=$text.Substring($start,$end-$start)

$bad=@'
        const graphValue=metric==="pf"&&d.pfUnknownPenalized?0.95:d.value;
        const y=top+plotH-(graphValue/max)*plotH;
'@

$good=@'
        const y=top+plotH-(d.value/max)*plotH;
'@

if($block.Contains($bad)){
    $block=$block.Replace($bad,$good)
}else{
    # fallback flexible
    $pattern='const\s+graphValue=metric==="pf"&&d\.pfUnknownPenalized\?0\.95:d\.value;\s*const\s+y=top\+plotH-\(graphValue/max\)\*plotH;'
    $new=[regex]::Replace($block,$pattern,'const y=top+plotH-(d.value/max)*plotH;',1)
    if($new -eq $block){
        throw "No encontré el graphValue incorrecto dentro de TariffSavingTrend."
    }
    $block=$new
}

$text=$text.Substring(0,$start)+$block+$text.Substring($end)

# Validación: dentro de TariffSavingTrend ya no debe existir metric
$check=$text.Substring($start,$text.IndexOf('function InvoiceTrend(',$start)-$start)
if($check -match '\bmetric\b'){
    throw "Todavía quedó una referencia a metric dentro de TariffSavingTrend."
}

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - error 'metric is not defined' corregido." -ForegroundColor Green
Write-Host "Se eliminó metric solamente de TariffSavingTrend." -ForegroundColor Yellow
Write-Host "InvoiceTrend conserva la lógica nueva de factor de potencia."
Write-Host "Backup: $backup"
