$ErrorActionPreference="Stop"
$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$front=$null
foreach($c in $candidates){if(Test-Path (Join-Path $c "app\page.tsx")){$front=$c;break}}
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_vercel_import_meta_v37_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw
$old='const API = (import.meta.env.VITE_API_URL as string) || "https://ahorro-energetico.onrender.com";'
$new='const API = (typeof process !== "undefined" && process.env?.NEXT_PUBLIC_API_URL) || "https://ahorro-energetico.onrender.com";'

if($page.Contains($old)){
  $page=$page.Replace($old,$new)
}elseif($page -notmatch 'NEXT_PUBLIC_API_URL'){
  $page=[regex]::Replace($page,'const\s+API\s*=\s*[^;]*VITE_API_URL[^;]*;',$new,1)
}

Set-Content $pagePath $page -Encoding UTF8

foreach($p in @((Join-Path $front ".next"),(Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if($check -match 'import\.meta\.env\.VITE_API_URL'){throw "Sigue presente import.meta.env.VITE_API_URL"}
if($check -notmatch 'NEXT_PUBLIC_API_URL'){throw "No se aplico NEXT_PUBLIC_API_URL"}

Write-Host ""
Write-Host "V37 aplicado correctamente." -ForegroundColor Green
Write-Host "El error de Vercel por import.meta.env.VITE_API_URL queda corregido." -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Read-Host "ENTER para cerrar"
