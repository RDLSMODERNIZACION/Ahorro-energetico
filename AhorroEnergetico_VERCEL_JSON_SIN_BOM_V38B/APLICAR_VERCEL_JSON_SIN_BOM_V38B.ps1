$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - VERCEL.JSON SIN BOM V38B" -ForegroundColor Cyan
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

$vercelPath=Join-Path $front "vercel.json"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_vercel_json_v38b_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null

if(Test-Path $vercelPath){
  Copy-Item $vercelPath (Join-Path $backup "vercel.json") -Force
}

$json=@'
{
  "buildCommand": "rm -rf .next && npx next build"
}
'@

# IMPORTANTE: escribir UTF-8 SIN BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($vercelPath, $json, $utf8NoBom)

# Verificar que el primer byte NO sea EF BB BF
$bytes=[System.IO.File]::ReadAllBytes($vercelPath)
$hasBom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

Write-Host "[OK] vercel.json reescrito." -ForegroundColor Green
Write-Host "BOM presente: $hasBom"

if($hasBom){
  throw "vercel.json sigue teniendo BOM."
}

# Validar JSON localmente
try {
  $null = Get-Content $vercelPath -Raw | ConvertFrom-Json
  Write-Host "[OK] JSON valido." -ForegroundColor Green
}catch{
  throw "vercel.json no es JSON valido: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Contenido final:" -ForegroundColor Cyan
Get-Content $vercelPath

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V38B APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora subi el cambio a GitHub:" -ForegroundColor White
Write-Host "  git add front/vercel.json" -ForegroundColor Green
Write-Host "  git commit -m `"Fix vercel json encoding`"" -ForegroundColor Green
Write-Host "  git push" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
