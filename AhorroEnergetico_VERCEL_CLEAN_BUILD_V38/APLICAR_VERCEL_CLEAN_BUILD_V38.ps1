$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - VERCEL CLEAN BUILD V38" -ForegroundColor Cyan
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
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "package.json"))){
    $front=$c
    break
  }
}
if(-not $front){ throw "No encontre la carpeta front." }

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_vercel_clean_v38_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null

$pagePath=Join-Path $front "app\page.tsx"
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$vercelPath=Join-Path $front "vercel.json"
if(Test-Path $vercelPath){
  Copy-Item $vercelPath (Join-Path $backup "vercel.json") -Force
}

# -----------------------------------------------------------------
# 1. Asegurar que page.tsx no use import.meta.env.VITE_API_URL
# -----------------------------------------------------------------
$page=Get-Content $pagePath -Raw

$page=[regex]::Replace(
  $page,
  'const\s+API\s*=\s*[^;]*VITE_API_URL[^;]*;',
  'const API = "https://ahorro-energetico.onrender.com";',
  1
)

# También eliminamos NEXT_PUBLIC_API_URL para esta versión:
# el backend es conocido y así no queda ninguna evaluación de entorno
# durante prerender.
$page=[regex]::Replace(
  $page,
  'const\s+API\s*=\s*\(typeof process !== "undefined" && process\.env\?\.NEXT_PUBLIC_API_URL\)\s*\|\|\s*"https://ahorro-energetico\.onrender\.com";',
  'const API = "https://ahorro-energetico.onrender.com";',
  1
)

Set-Content $pagePath $page -Encoding UTF8

# -----------------------------------------------------------------
# 2. Crear vercel.json para BORRAR .next después de restaurar cache.
#    Esto es importante porque el log sigue diciendo:
#    "Restored build cache from previous deployment"
# -----------------------------------------------------------------
$vercel=@'
{
  "buildCommand": "rm -rf .next && npx next build"
}
'@
Set-Content $vercelPath $vercel -Encoding UTF8

# -----------------------------------------------------------------
# 3. Buscar VITE_API_URL en fuentes activas.
#    Excluimos backups, node_modules y carpetas de fixes viejos.
# -----------------------------------------------------------------
$extensions=@("*.ts","*.tsx","*.js","*.jsx","*.mjs","*.cjs")
$hits=@()

foreach($ext in $extensions){
  $files=Get-ChildItem $front -Recurse -File -Filter $ext -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -notmatch '\\node_modules\\' -and
      $_.FullName -notmatch '\\backup_' -and
      $_.FullName -notmatch '\\AhorroEnergetico_' -and
      $_.FullName -notmatch '\\FRONT_CONECTADO\\' -and
      $_.FullName -notmatch '\\APLICAR_SIN_DIRAC\\' -and
      $_.FullName -notmatch '\\dist\\' -and
      $_.FullName -notmatch '\\.next\\'
    }

  foreach($f in $files){
    $matches=Select-String -Path $f.FullName -Pattern 'VITE_API_URL' -SimpleMatch -ErrorAction SilentlyContinue
    if($matches){ $hits += $f.FullName }
  }
}

Write-Host ""
if($hits.Count -gt 0){
  Write-Host "[WARN] Todavia encontre VITE_API_URL en fuentes activas:" -ForegroundColor Yellow
  $hits | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  Write-Host ""
  Write-Host "No las modifico automaticamente para no romper archivos desconocidos." -ForegroundColor Yellow
}else{
  Write-Host "[OK] No queda VITE_API_URL en fuentes activas." -ForegroundColor Green
}

# -----------------------------------------------------------------
# 4. Limpiar local
# -----------------------------------------------------------------
foreach($p in @(
  (Join-Path $front ".next"),
  (Join-Path $front "node_modules\.cache"),
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite")
)){
  if(Test-Path $p){ Remove-Item $p -Recurse -Force }
}

# -----------------------------------------------------------------
# 5. Verificación
# -----------------------------------------------------------------
$check=Get-Content $pagePath -Raw
$okApi=$check -match 'const API = "https://ahorro-energetico\.onrender\.com";'
$okVercel=(Test-Path $vercelPath) -and ((Get-Content $vercelPath -Raw) -match 'rm -rf \.next && npx next build')

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  API hardcodeada y segura para prerender: $okApi"
Write-Host "  Vercel borra .next antes de compilar: $okVercel"

if(-not $okApi -or -not $okVercel){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V38 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANTE:" -ForegroundColor Yellow
Write-Host "El log de Vercel seguia restaurando cache." -ForegroundColor Yellow
Write-Host "Ahora, aunque Vercel restaure cache, el build borra .next antes de compilar." -ForegroundColor Green
Write-Host ""
Write-Host "Luego hace:" -ForegroundColor White
Write-Host "  rm -rf .next && npx next build" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
