$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - IA V2 INTELIGENTE V45" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$root=$null
foreach($c in @($here,(Split-Path -Parent $here))){
  if((Test-Path (Join-Path $c "front\app\page.tsx")) -and
     (Test-Path (Join-Path $c "back\app\routers\ai.py"))){$root=$c;break}
}
if(-not $root){throw "No encontre front y back del proyecto."}

$packageDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$payload=Join-Path $packageDir "payload"
$pagePath=Join-Path $root "front\app\page.tsx"
$aiPath=Join-Path $root "back\app\routers\ai.py"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_ia_v2_v45_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $aiPath (Join-Path $backup "ai.py") -Force

# Backend completo, para evitar parches frágiles.
Copy-Item (Join-Path $payload "ai.py") $aiPath -Force

# Front: reemplazar preguntas sugeridas por preguntas accionables.
$page=Get-Content $pagePath -Raw

$replacements=@{
  '¿Qué medidores tienen cos φ bajo?'='¿Qué 5 acciones me hacen ahorrar más este mes?'
  '¿Dónde sobra más potencia contratada?'='¿Qué suministros parecen estar sobredimensionados?'
  '¿Qué facturas faltan este mes?'='¿Qué suministros podrían estar fuera de uso?'
  '¿Cuáles son los mayores ahorros?'='¿Dónde tengo penalización por factor de potencia?'
  '¿Cuáles son los mayores consumos?'='¿Qué consumos aumentaron anormalmente este mes?'
}
foreach($k in $replacements.Keys){$page=$page.Replace($k,$replacements[$k])}

# Placeholder más útil.
$page=$page.Replace(
  'Ej.: ¿Qué medidores conviene revisar primero?',
  'Ej.: ¿Qué 5 acciones concretas debería hacer primero para ahorrar este mes?'
)

Set-Content $pagePath $page -Encoding UTF8

# Verificación
$checkAi=Get-Content $aiPath -Raw
$checkPage=Get-Content $pagePath -Raw

$okIntent=$checkAi -match '_detect_intent'
$okRelevant=$checkAi -match 'relevant_detail'
$okInactive=$checkAi -match 'inactive_supply'
$okPrompts=$checkPage -match '¿Qué 5 acciones me hacen ahorrar más este mes\?'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Router de intención: $okIntent"
Write-Host "  Contexto específico: $okRelevant"
Write-Host "  Posibles bajas con historial: $okInactive"
Write-Host "  Preguntas nuevas: $okPrompts"

if(-not $okIntent -or -not $okRelevant -or -not $okInactive -or -not $okPrompts){
  throw "La verificacion final fallo."
}

foreach($p in @(
  (Join-Path $root "front\.next"),
  (Join-Path $root "front\node_modules\.vite"),
  (Join-Path $root "front\.vite")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V45 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "La IA ahora detecta qué estás preguntando y prepara datos específicos." -ForegroundColor Green
Write-Host "No manda el mismo contexto genérico para todas las preguntas." -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
