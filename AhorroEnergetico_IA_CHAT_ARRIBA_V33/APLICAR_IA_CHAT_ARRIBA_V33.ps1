$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - CHAT IA ARRIBA V33" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_ia_chat_arriba_v33_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# Localizar bloque completo ai-chat.
$rxChat=New-Object System.Text.RegularExpressions.Regex(
  '(?s)\s*<section className="panel ai-chat">.*?</section>',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$match=$rxChat.Match($page)
if(-not $match.Success){
  throw "No encontre el bloque <section className=`"panel ai-chat`">."
}

$chatBlock=$match.Value.Trim()

# Quitar chat de su posición actual.
$page=$rxChat.Replace($page,'',1)

# Insertarlo inmediatamente después del cuadro verde ai-hero.
$rxHero=New-Object System.Text.RegularExpressions.Regex(
  '(?s)(<section className="panel ai-hero">.*?</section>)',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if(-not $rxHero.IsMatch($page)){
  throw "No encontre el cuadro verde ai-hero."
}

$page=$rxHero.Replace($page,'$1'+"`r`n`r`n    "+$chatBlock,1)

Set-Content $pagePath $page -Encoding UTF8

# CSS: dar un pequeño margen para que quede visualmente integrado.
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace(
  $css,
  '(?s)/\* === IA CHAT ARRIBA V33 START === \*/.*?/\* === IA CHAT ARRIBA V33 END === \*/',
  ''
)

$block=@'

/* === IA CHAT ARRIBA V33 START === */
.ai-module > .ai-hero + .ai-chat{
  margin-top:0;
  margin-bottom:0;
}
.ai-module > .ai-chat + .ai-alert-grid,
.ai-module > .ai-chat + .ai-smart-sections{
  margin-top:0;
}
/* === IA CHAT ARRIBA V33 END === */
'@

$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# Limpiar cache Vite.
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificación de orden.
$check=Get-Content $pagePath -Raw
$heroPos=$check.IndexOf('<section className="panel ai-hero">')
$chatPos=$check.IndexOf('<section className="panel ai-chat">')
$alertsPos=$check.IndexOf('ai-alert-grid')
$smartPos=$check.IndexOf('ai-smart-sections')

$nextContentPos=-1
if($alertsPos -ge 0){$nextContentPos=$alertsPos}
if($smartPos -ge 0 -and ($nextContentPos -lt 0 -or $smartPos -lt $nextContentPos)){$nextContentPos=$smartPos}

$okOrder=($heroPos -ge 0 -and $chatPos -gt $heroPos -and ($nextContentPos -lt 0 -or $chatPos -lt $nextContentPos))

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Hero IA:    $heroPos"
Write-Host "  Chat IA:    $chatPos"
Write-Host "  Alertas:    $nextContentPos"
Write-Host "  Orden OK:   $okOrder"

if(-not $okOrder){
  throw "El chat no quedo en la posicion esperada."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V33 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora el orden de la pantalla IA es:" -ForegroundColor White
Write-Host "  1. Cuadro verde IA" -ForegroundColor Green
Write-Host "  2. Chat / Preguntale a la base" -ForegroundColor Green
Write-Host "  3. Indicadores y alertas" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
