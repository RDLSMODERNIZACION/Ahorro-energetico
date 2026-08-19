$ErrorActionPreference = "Stop"
$package = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $package
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "Aplicando modulo de encuadramiento tarifario..." -ForegroundColor Cyan
$front = Join-Path $root "front"
$back = Join-Path $root "back"

if (-not (Test-Path (Join-Path $front "app\page.tsx"))) {
    $page = Get-ChildItem -Path $root -Filter page.tsx -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "node_modules|ENCUADRAMIENTO_TARIFARIO|payload" } | Select-Object -First 1
    if ($page) { $front = Split-Path -Parent (Split-Path -Parent $page.FullName) }
}
if (-not (Test-Path (Join-Path $back "app\routers\analysis.py"))) {
    $router = Get-ChildItem -Path $root -Filter analysis.py -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "app[\\/]routers" -and $_.FullName -notmatch "ENCUADRAMIENTO_TARIFARIO|payload" } | Select-Object -First 1
    if ($router) { $back = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $router.FullName)) }
}

$targets = @(
    @{ Source="payload\front\app\page.tsx"; Target=(Join-Path $front "app\page.tsx") },
    @{ Source="payload\front\app\globals.css"; Target=(Join-Path $front "app\globals.css") },
    @{ Source="payload\front\app\analysis-charts.tsx"; Target=(Join-Path $front "app\analysis-charts.tsx") },
    @{ Source="payload\back\app\routers\invoices.py"; Target=(Join-Path $back "app\routers\invoices.py") },
    @{ Source="payload\back\app\routers\analysis.py"; Target=(Join-Path $back "app\routers\analysis.py") },
    @{ Source="payload\back\app\main.py"; Target=(Join-Path $back "app\main.py") },
    @{ Source="payload\back\app\config.py"; Target=(Join-Path $back "app\config.py") },
    @{ Source="payload\back\app\db.py"; Target=(Join-Path $back "app\db.py") },
    @{ Source="payload\back\app\auth.py"; Target=(Join-Path $back "app\auth.py") }
)
foreach ($item in $targets) {
    $source=Join-Path $package $item.Source
    if (Test-Path $item.Target) {
        Copy-Item $item.Target "$($item.Target).bak-$stamp" -Force
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $item.Target) -Force | Out-Null
    }
    Copy-Item $source $item.Target -Force
    Write-Host "Actualizado: $($item.Target)" -ForegroundColor Green
}
$seedDir=Join-Path $back "supabase"
New-Item -ItemType Directory -Path $seedDir -Force | Out-Null
Copy-Item (Join-Path $package "payload\back\supabase\seed_tariff_2026_07.sql") (Join-Path $seedDir "seed_tariff_2026_07.sql") -Force
Write-Host "Incluido: cuadro tarifario EPEN 041/2026" -ForegroundColor Green
Write-Host ""
Write-Host "Modulo aplicado. Proba el frontend y luego subi front/back a GitHub." -ForegroundColor Green
Read-Host "Presiona ENTER para cerrar"
