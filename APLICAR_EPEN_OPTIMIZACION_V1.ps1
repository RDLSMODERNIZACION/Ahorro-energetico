$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = (Resolve-Path (Join-Path $Root "..")).Path

if (-not (Test-Path (Join-Path $Repo "back\app\main.py"))) { throw "Ejecutá este ZIP descomprimido dentro de la raíz del repositorio Ahorro-energetico." }
if (-not (Test-Path (Join-Path $Repo "front\app\page.tsx"))) { throw "No encontré front\app\page.tsx." }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $Root "backup_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item (Join-Path $Repo "back\app\main.py") $backup
Copy-Item (Join-Path $Repo "front\app\page.tsx") $backup

Copy-Item (Join-Path $Root "payload\back\app\routers\epen_optimization.py") (Join-Path $Repo "back\app\routers\epen_optimization.py") -Force
Copy-Item (Join-Path $Root "payload\front\app\epen-optimization-panel.tsx") (Join-Path $Repo "front\app\epen-optimization-panel.tsx") -Force
Copy-Item (Join-Path $Root "payload\front\app\epen-optimization.module.css") (Join-Path $Repo "front\app\epen-optimization.module.css") -Force

$mainPath = Join-Path $Repo "back\app\main.py"
$main = Get-Content $mainPath -Raw
if ($main -notmatch "epen_optimization") {
  $main = $main.Replace("from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence", "from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization")
  $main = $main.Replace('api.include_router(analysis.router,prefix="/api")', 'api.include_router(analysis.router,prefix="/api")' + "`r`n" + 'api.include_router(epen_optimization.router,prefix="/api")')
  Set-Content $mainPath $main -Encoding UTF8
}

$pagePath = Join-Path $Repo "front\app\page.tsx"
$page = Get-Content $pagePath -Raw
if ($page -notmatch 'EpenOptimizationPanel') {
  $page = $page.Replace('import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";', 'import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";' + "`r`n" + 'import { EpenOptimizationPanel } from "./epen-optimization-panel";')
  $needle = '{tab==="framing"&&<>'
  $replacement = '{tab==="framing"&&<><EpenOptimizationPanel session={session} organizationId={orgId||""} onOpenMeter={openMeterById}/>'
  if (-not $page.Contains($needle)) { throw "No encontré el punto de inserción del módulo Encuadre en page.tsx. No modifiqué page.tsx." }
  $page = $page.Replace($needle, $replacement)
  Set-Content $pagePath $page -Encoding UTF8
}

Write-Host "OK - Optimización EPEN instalada." -ForegroundColor Green
Write-Host "Backend: /api/organizations/{organization_id}/epen-optimization"
Write-Host "Frontend: módulo agregado al inicio de Encuadre / Ahorro."
Write-Host "Backup: $backup"
