$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# El ZIP puede descomprimirse directamente en la raíz del repo
# o quedar dentro de una subcarpeta. Detectamos ambos casos.
$Repo = $null

if (
    (Test-Path (Join-Path $Root "back\app\main.py")) -and
    (Test-Path (Join-Path $Root "front\app\page.tsx"))
) {
    $Repo = $Root
}
else {
    $Parent = (Resolve-Path (Join-Path $Root "..")).Path
    if (
        (Test-Path (Join-Path $Parent "back\app\main.py")) -and
        (Test-Path (Join-Path $Parent "front\app\page.tsx"))
    ) {
        $Repo = $Parent
    }
}

if (-not $Repo) {
    throw "No encontré back\app\main.py y front\app\page.tsx. Ejecutá este script desde la raíz de Ahorro-energetico o desde una subcarpeta dentro del repositorio."
}

Write-Host "Repositorio detectado: $Repo" -ForegroundColor Cyan

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $Root "backup_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item (Join-Path $Repo "back\app\main.py") $backup
Copy-Item (Join-Path $Repo "front\app\page.tsx") $backup

# Detectar payload tanto si quedó en el mismo directorio como si está en una subcarpeta payload.
$PayloadRoot = Join-Path $Root "payload"
if (-not (Test-Path $PayloadRoot)) {
    throw "No encontré la carpeta payload junto al script. Descomprimí el ZIP completo, no solo el .ps1."
}

Copy-Item (Join-Path $PayloadRoot "back\app\routers\epen_optimization.py") (Join-Path $Repo "back\app\routers\epen_optimization.py") -Force
Copy-Item (Join-Path $PayloadRoot "front\app\epen-optimization-panel.tsx") (Join-Path $Repo "front\app\epen-optimization-panel.tsx") -Force
Copy-Item (Join-Path $PayloadRoot "front\app\epen-optimization.module.css") (Join-Path $Repo "front\app\epen-optimization.module.css") -Force

$mainPath = Join-Path $Repo "back\app\main.py"
$main = Get-Content $mainPath -Raw

if ($main -notmatch "epen_optimization") {
    $oldImport = "from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence"
    $newImport = "from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization"

    if (-not $main.Contains($oldImport)) {
        throw "No encontré la línea de imports esperada en back\app\main.py. Se creó backup y no se modificó main.py."
    }

    $main = $main.Replace($oldImport, $newImport)

    $oldRouter = 'api.include_router(analysis.router,prefix="/api")'
    $newRouter = $oldRouter + "`r`n" + 'api.include_router(epen_optimization.router,prefix="/api")'

    if (-not $main.Contains($oldRouter)) {
        throw "No encontré el punto de inserción del router analysis en back\app\main.py."
    }

    $main = $main.Replace($oldRouter, $newRouter)
    Set-Content $mainPath $main -Encoding UTF8
}

$pagePath = Join-Path $Repo "front\app\page.tsx"
$page = Get-Content $pagePath -Raw

if ($page -notmatch 'EpenOptimizationPanel') {
    $oldImport = 'import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";'
    $newImport = $oldImport + "`r`n" + 'import { EpenOptimizationPanel } from "./epen-optimization-panel";'

    if (-not $page.Contains($oldImport)) {
        throw "No encontré el import de InvoiceAnalysisPanel en front\app\page.tsx."
    }

    $page = $page.Replace($oldImport, $newImport)

    $needle = '{tab==="framing"&&<>'
    $replacement = '{tab==="framing"&&<><EpenOptimizationPanel session={session} organizationId={orgId||""} onOpenMeter={openMeterById}/>'

    if (-not $page.Contains($needle)) {
        throw "No encontré el punto de inserción del módulo Encuadre en page.tsx."
    }

    $page = $page.Replace($needle, $replacement)
    Set-Content $pagePath $page -Encoding UTF8
}

Write-Host ""
Write-Host "OK - Optimización EPEN instalada." -ForegroundColor Green
Write-Host "Backend: /api/organizations/{organization_id}/epen-optimization"
Write-Host "Frontend: módulo agregado al inicio de Encuadre / Ahorro."
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Ahora podés ejecutar:" -ForegroundColor Yellow
Write-Host "  git diff"
Write-Host "  cd back"
Write-Host "  python -m uvicorn app.main:app --reload"
