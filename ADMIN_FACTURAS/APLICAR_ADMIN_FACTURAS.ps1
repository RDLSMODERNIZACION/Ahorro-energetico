$ErrorActionPreference = "Stop"
$package = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $package
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "Aplicando administrador mensual y detalle de medidores..." -ForegroundColor Cyan

$front = Join-Path $root "front"
$back = Join-Path $root "back"

if (-not (Test-Path (Join-Path $front "app\page.tsx"))) {
    $page = Get-ChildItem -Path $root -Filter page.tsx -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "node_modules|ADMIN_FACTURAS|payload" } |
        Select-Object -First 1
    if ($page) { $front = Split-Path -Parent (Split-Path -Parent $page.FullName) }
}

if (-not (Test-Path (Join-Path $back "app\routers\invoices.py"))) {
    $invoiceRouter = Get-ChildItem -Path $root -Filter invoices.py -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "app[\\/]routers" -and $_.FullName -notmatch "ADMIN_FACTURAS|payload" } |
        Select-Object -First 1
    if ($invoiceRouter) { $back = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $invoiceRouter.FullName)) }
}

$targets = @(
    @{ Source = "payload\front\app\page.tsx"; Target = (Join-Path $front "app\page.tsx") },
    @{ Source = "payload\front\app\globals.css"; Target = (Join-Path $front "app\globals.css") },
    @{ Source = "payload\back\app\routers\invoices.py"; Target = (Join-Path $back "app\routers\invoices.py") }
)

foreach ($item in $targets) {
    $source = Join-Path $package $item.Source
    if (-not (Test-Path $item.Target)) { throw "No encontre el archivo destino: $($item.Target)" }
    Copy-Item $item.Target "$($item.Target).bak-$stamp" -Force
    Copy-Item $source $item.Target -Force
    Write-Host "Actualizado: $($item.Target)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Cambios aplicados correctamente." -ForegroundColor Green
Write-Host "Para probar el frontend:" -ForegroundColor Yellow
Write-Host "  cd `"$front`""
Write-Host "  npx vite"
Write-Host ""
Write-Host "El backend debe subirse a GitHub para que Render vuelva a desplegarlo."
Read-Host "Presiona ENTER para cerrar"
