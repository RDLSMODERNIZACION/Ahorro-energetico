$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "Conectando frontend con Render y Supabase..." -ForegroundColor Green
$root = Split-Path $PSScriptRoot -Parent

if (-not ((Test-Path (Join-Path $root "package.json")) -and (Test-Path (Join-Path $root "app\page.tsx")))) {
  Write-Host "No encontre el frontend en: $root" -ForegroundColor Red
  Write-Host "Extrae el ZIP dentro de C:\Users\administrador\Documents\Ahorro-energetico"
  Read-Host "Presiona ENTER para cerrar"; exit 1
}

$backup = Join-Path $root ("backup_front_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path (Join-Path $backup "app") | Out-Null
Copy-Item (Join-Path $root "app\page.tsx") (Join-Path $backup "app\page.tsx") -Force
Copy-Item (Join-Path $root "app\globals.css") (Join-Path $backup "app\globals.css") -Force
Copy-Item (Join-Path $root "package.json") (Join-Path $backup "package.json") -Force
if (Test-Path (Join-Path $root "package-lock.json")) { Copy-Item (Join-Path $root "package-lock.json") (Join-Path $backup "package-lock.json") -Force }

New-Item -ItemType Directory -Force -Path (Join-Path $root "app\lib") | Out-Null
Copy-Item ".\payload\app\page.tsx" (Join-Path $root "app\page.tsx") -Force
Copy-Item ".\payload\app\globals.css" (Join-Path $root "app\globals.css") -Force
Copy-Item ".\payload\app\lib\supabase.ts" (Join-Path $root "app\lib\supabase.ts") -Force
Copy-Item ".\payload\package.json" (Join-Path $root "package.json") -Force
Copy-Item ".\payload\package-lock.json" (Join-Path $root "package-lock.json") -Force
Copy-Item ".\payload\.env.local" (Join-Path $root ".env.local") -Force

Write-Host "Instalando dependencias..." -ForegroundColor Cyan
Push-Location $root
npm install
Pop-Location

Write-Host "" 
Write-Host "FRONTEND CONECTADO CORRECTAMENTE" -ForegroundColor Green
Write-Host "Variables locales creadas en .env.local."
Write-Host "Para iniciarlo, desde la raiz ejecuta: npm run dev" -ForegroundColor Cyan
Write-Host "Backup creado en: $backup" -ForegroundColor Yellow
Read-Host "Presiona ENTER para cerrar"
