$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$page = Join-Path $repo "front\app\page.tsx"
$frontPanel = Join-Path $repo "front\app\public-lighting-panel.tsx"
$backRouter = Join-Path $repo "back\app\routers\public_lighting.py"

$srcFront = Join-Path $scriptDir "payload\front\app\public-lighting-panel.tsx"
$srcBack = Join-Path $scriptDir "payload\back\app\routers\public_lighting.py"

foreach($f in @($page,$frontPanel,$backRouter,$srcFront,$srcBack)){
  if(-not (Test-Path $f)){ throw "No encontré: $f" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $page "$page.bak-$stamp" -Force
Copy-Item $frontPanel "$frontPanel.bak-$stamp" -Force
Copy-Item $backRouter "$backRouter.bak-$stamp" -Force

Copy-Item $srcFront $frontPanel -Force
Copy-Item $srcBack $backRouter -Force

# Asegurar que page.tsx pase a AP los mismos arrays que usa el análisis general.
$pageText = Get-Content $page -Raw -Encoding UTF8

$already = $pageText -match '<PublicLightingPanel[\s\S]*?invoices=\{invoices\}[\s\S]*?tariffSavings=\{tariffSavings\}[\s\S]*?epenOptimization=\{epenOptimization\}'
if(-not $already){
  $pattern = '\{invoiceSubTab\s*={2,3}\s*"publicLighting"\s*&&\s*<PublicLightingPanel[\s\S]*?/>\s*\}'
  $rx = [regex]::new($pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
  if(-not $rx.IsMatch($pageText)){
    throw "No encontré la llamada a PublicLightingPanel en page.tsx."
  }

  $replacement = @'
{invoiceSubTab==="publicLighting"&&<PublicLightingPanel
  session={session}
  organizationId={orgId||""}
  invoices={invoices}
  tariffSavings={tariffSavings}
  epenOptimization={epenOptimization}
/>}
'@

  $pageText = $rx.Replace($pageText,$replacement,1)
  Set-Content $page -Value $pageText -Encoding UTF8
}

Write-Host ""
Write-Host "CODIGO V4 aplicado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANTE: todavía falta ejecutar el SQL del ZIP en Supabase." -ForegroundColor Yellow
Write-Host "Archivo: supabase\001_ap_como_clasificacion.sql"
Write-Host ""
Write-Host "Luego reiniciá backend y frontend." -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
