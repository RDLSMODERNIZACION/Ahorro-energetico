$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - VERCEL FIX METER LOCATION V39" -ForegroundColor Cyan
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
  if(Test-Path (Join-Path $c "app\meter-location-editor.tsx")){
    $front=$c
    break
  }
}
if(-not $front){ throw "No encontre front\app\meter-location-editor.tsx." }

$file=Join-Path $front "app\meter-location-editor.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_vercel_meter_location_v39_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $file (Join-Path $backup "meter-location-editor.tsx") -Force

$content=Get-Content $file -Raw

$old='const API=(import.meta.env.VITE_API_URL as string)||"https://ahorro-energetico.onrender.com";'
$new='const API="https://ahorro-energetico.onrender.com";'

if($content.Contains($old)){
  $content=$content.Replace($old,$new)
}else{
  $content=[regex]::Replace(
    $content,
    'const\s+API\s*=\s*\(import\.meta\.env\.VITE_API_URL as string\)\s*\|\|\s*"https://ahorro-energetico\.onrender\.com";',
    $new,
    1
  )
}

Set-Content $file $content -Encoding UTF8

# Buscar cualquier VITE_API_URL restante dentro de app/ activo
$hits=Get-ChildItem (Join-Path $front "app") -Recurse -File -Include *.ts,*.tsx,*.js,*.jsx,*.mjs |
  Where-Object { $_.FullName -notmatch '\\backup_' } |
  Select-String -Pattern 'VITE_API_URL' -SimpleMatch -ErrorAction SilentlyContinue

Write-Host ""
if($hits){
  Write-Host "[WARN] Todavia quedan referencias VITE_API_URL en app/:" -ForegroundColor Yellow
  $hits | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber) $($_.Line.Trim())" -ForegroundColor Yellow }
  throw "Todavia quedan referencias activas a VITE_API_URL."
}else{
  Write-Host "[OK] No queda VITE_API_URL en front/app." -ForegroundColor Green
}

# Limpiar caches
foreach($p in @(
  (Join-Path $front ".next"),
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V39 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Se corrigio el archivo que seguia rompiendo Vercel:" -ForegroundColor White
Write-Host " front/app/meter-location-editor.tsx" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
