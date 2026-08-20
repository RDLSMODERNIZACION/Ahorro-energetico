$ErrorActionPreference = "Stop"

$paquete = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $paquete
$front = Join-Path $raiz "front"
$back = Join-Path $raiz "back"

if (-not (Test-Path (Join-Path $front "app\page.tsx"))) {
    Write-Host "No encontre el frontend en: $front" -ForegroundColor Red
    Write-Host "Extrae esta carpeta dentro de C:\Users\administrador\Documents\Ahorro-energetico" -ForegroundColor Yellow
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}

if (-not (Test-Path (Join-Path $back "app\routers\invoices.py"))) {
    Write-Host "No encontre el backend en: $back" -ForegroundColor Red
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}

$marca = Get-Date -Format "yyyyMMdd-HHmmss"
$respaldo = Join-Path $raiz "RESPALDO_GRAFICOS_$marca"
New-Item -ItemType Directory -Path (Join-Path $respaldo "front\app") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $respaldo "back\app\routers") -Force | Out-Null

Copy-Item (Join-Path $front "app\page.tsx") (Join-Path $respaldo "front\app\page.tsx") -Force
Copy-Item (Join-Path $front "app\analysis-charts.tsx") (Join-Path $respaldo "front\app\analysis-charts.tsx") -Force
Copy-Item (Join-Path $back "app\routers\invoices.py") (Join-Path $respaldo "back\app\routers\invoices.py") -Force

Copy-Item (Join-Path $paquete "payload\front\app\page.tsx") (Join-Path $front "app\page.tsx") -Force
Copy-Item (Join-Path $paquete "payload\front\app\analysis-charts.tsx") (Join-Path $front "app\analysis-charts.tsx") -Force
Copy-Item (Join-Path $paquete "payload\back\app\routers\invoices.py") (Join-Path $back "app\routers\invoices.py") -Force

Write-Host "" 
Write-Host "Correccion aplicada correctamente." -ForegroundColor Green
Write-Host "Respaldo creado en: $respaldo" -ForegroundColor Cyan
Write-Host "" 
Write-Host "Siguiente paso:" -ForegroundColor Yellow
Write-Host "1. Subi los cambios a GitHub para que Render y Vercel vuelvan a desplegar." 
Write-Host "2. Cuando ambos deploys terminen, recarga el navegador con Ctrl+F5." 
Write-Host "" 
Read-Host "Presiona ENTER para cerrar"
