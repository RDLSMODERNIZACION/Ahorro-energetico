$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - SIDEBAR LIMPIA V42" -ForegroundColor Cyan
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
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_sidebar_limpia_v42_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

# Quitar botones de Encuadramiento y Ahorros del sidebar.
$page=[regex]::Replace(
  $page,
  '<button[^>]*onClick=\{\(\)=>setTab\("framing"\)\}[^>]*>.*?</button>',
  '',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)
$page=[regex]::Replace(
  $page,
  '<button[^>]*onClick=\{\(\)=>setTab\("tariffs"\)\}[^>]*>.*?</button>',
  '',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

# Mover IA justo debajo de Facturas.
$rxAi=New-Object System.Text.RegularExpressions.Regex(
  '(?s)\s*<button[^>]*onClick=\{\(\)=>setTab\("ai"\)\}[^>]*>.*?</button>',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)
$aiMatch=$rxAi.Match($page)
if(-not $aiMatch.Success){throw "No encontre boton IA en sidebar."}
$aiBlock=$aiMatch.Value.Trim()
$page=$rxAi.Replace($page,'',1)

$rxInvoices=New-Object System.Text.RegularExpressions.Regex(
  '(?s)(<button[^>]*onClick=\{\(\)=>setTab\("invoices"\)\}[^>]*>.*?</button>)',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)
if(-not $rxInvoices.IsMatch($page)){throw "No encontre boton Facturas en sidebar."}
$page=$rxInvoices.Replace($page,'$1'+"`r`n"+$aiBlock,1)

Set-Content $pagePath $page -Encoding UTF8

$check=Get-Content $pagePath -Raw
$hasFraming=$check -match 'setTab\("framing"\)'
$hasTariffs=$check -match 'setTab\("tariffs"\)'
$factPos=$check.IndexOf('setTab("invoices")')
$aiPos=$check.IndexOf('setTab("ai")')
$metersPos=$check.IndexOf('setTab("map")')
$okOrder=($factPos -ge 0 -and $aiPos -gt $factPos -and ($metersPos -lt 0 -or $aiPos -lt $metersPos))

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Encuadramiento sidebar eliminado: $(-not $hasFraming)"
Write-Host "  Ahorros sidebar eliminado: $(-not $hasTariffs)"
Write-Host "  IA debajo de Facturas: $okOrder"

if($hasFraming -or $hasTariffs -or -not $okOrder){
  throw "La verificacion final fallo."
}

foreach($p in @((Join-Path $front ".next"),(Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "V42 aplicado correctamente." -ForegroundColor Green
Write-Host "Sidebar final: Resumen -> Facturas -> IA -> Medidores" -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
