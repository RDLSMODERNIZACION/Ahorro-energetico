$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - TABLA UNICA DE FACTURAS V3" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @(
    (Get-Location).Path,
    (Join-Path (Get-Location).Path "front"),
    (Split-Path -Parent $scriptDir),
    (Join-Path (Split-Path -Parent $scriptDir) "front")
) | Select-Object -Unique

$front = $null
foreach($candidate in $candidates){
    if((Test-Path (Join-Path $candidate "app\page.tsx")) -and
       (Test-Path (Join-Path $candidate "app\layout.tsx"))){
        $front = $candidate
        break
    }
}

if(-not $front){
    Write-Host "No pude detectar Ahorro-energetico\front." -ForegroundColor Red
    Write-Host "Abri PowerShell dentro de la carpeta front y volve a ejecutar." -ForegroundColor Yellow
    Read-Host "ENTER para salir"
    exit 1
}

$pagePath   = Join-Path $front "app\page.tsx"
$layoutPath = Join-Path $front "app\layout.tsx"
$cssTarget  = Join-Path $front "app\table-single-invoices.css"
$cssSource  = Join-Path $scriptDir "table-single-invoices.css"

Write-Host "Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White
Write-Host ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $front "backup_tabla_unica_v3_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $layoutPath (Join-Path $backup "layout.tsx") -Force

$page = Get-Content $pagePath -Raw

# ----------------------------------------------------------------
# 1) Cambiar la llamada: una sola InvoiceTable recibe tambien faltantes.
#    Soporta tanto el codigo original como el FIX V2 anterior.
# ----------------------------------------------------------------
$originalCall = '<InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} onSelect={openMeter}/><MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod}/>'
$v2Call = '<div className="invoice-unified-scroll"><InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} onSelect={openMeter}/><MissingInvoiceTable meters={visibleMissingPeriodMeters} period={controlPeriod}/></div>'
$newCall = '<InvoiceTable invoices={filteredInvoices} assessments={assessments} tariffSavings={tariffSavings} pendingMeters={visibleMissingPeriodMeters} period={controlPeriod} onSelect={openMeter}/>'

if($page.Contains($v2Call)){
    $page = $page.Replace($v2Call,$newCall)
    Write-Host "[OK] Quite el contenedor V2 y unifique la llamada." -ForegroundColor Green
}
elseif($page.Contains($originalCall)){
    $page = $page.Replace($originalCall,$newCall)
    Write-Host "[OK] Unifique la llamada de las dos tablas." -ForegroundColor Green
}
elseif($page -match 'pendingMeters=\{visibleMissingPeriodMeters\}'){
    Write-Host "[OK] La llamada V3 ya estaba aplicada." -ForegroundColor DarkGreen
}
else{
    throw "No encontre la llamada de InvoiceTable + MissingInvoiceTable. No hice cambios."
}

# ----------------------------------------------------------------
# 2) Ampliar la firma de InvoiceTable
# ----------------------------------------------------------------
$oldSig = 'function InvoiceTable({invoices,assessments,tariffSavings,onSelect}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];onSelect?:(i:Invoice)=>void})'
$newSig = 'function InvoiceTable({invoices,assessments,tariffSavings,pendingMeters,period,onSelect}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];pendingMeters:Meter[];period:string;onSelect?:(i:Invoice)=>void})'

if($page.Contains($oldSig)){
    $page = $page.Replace($oldSig,$newSig)
    Write-Host "[OK] InvoiceTable ahora recibe las facturas pendientes." -ForegroundColor Green
}
elseif($page.Contains($newSig)){
    Write-Host "[OK] Firma V3 ya aplicada." -ForegroundColor DarkGreen
}
else{
    throw "No encontre la firma esperada de InvoiceTable."
}

# ----------------------------------------------------------------
# 3) Insertar filas pendientes DENTRO DEL MISMO tbody.
# ----------------------------------------------------------------
$oldTail = '})}{!invoices.length&&<tr><td colSpan={11}><div className="empty">No hay facturas para los filtros seleccionados.</div></td></tr>}</tbody></table></div>}'

$newTail = '})}{pendingMeters.length>0&&<><tr className="pending-section-row"><td colSpan={11}><div className="pending-section-content"><b>Facturas pendientes del período</b><span>{pendingMeters.length} filas pendientes</span></div></td></tr>{pendingMeters.map(m=>{const possibleRemoval=m.status==="inactive";return <tr key={`pending-${m.id}`} className={`pending-invoice-row${possibleRemoval?" possible-removal":""}`}><td><b>Medidor {m.meter_number||"S/D"}</b><small>{m.tracking_code||"Sin ID"}</small></td><td><b>{m.service_name||m.sites?.name||"Servicio sin nombre"}</b><small>Suministro {m.supply_number||"S/D"}</small></td><td><b>{period}</b><small>Factura faltante</small></td><td colSpan={7}><div className="pending-placeholder">{possibleRemoval?"Sin facturación reciente: posible baja, aún debe solicitarse la factura":`No se cargó una factura para este medidor en ${period}`}</div></td><td><span className="pending-badge">{possibleRemoval?"POSIBLE BAJA · PENDIENTE":"PENDIENTE"}</span></td></tr>})}</>}{!invoices.length&&!pendingMeters.length&&<tr><td colSpan={11}><div className="empty">No hay facturas para los filtros seleccionados.</div></td></tr>}</tbody></table></div>}'

if($page.Contains($oldTail)){
    $page = $page.Replace($oldTail,$newTail)
    Write-Host "[OK] Las pendientes fueron insertadas dentro de la misma tabla." -ForegroundColor Green
}
elseif($page -match 'pending-section-row'){
    Write-Host "[OK] Filas pendientes V3 ya insertadas." -ForegroundColor DarkGreen
}
else{
    throw "No encontre el cierre esperado de InvoiceTable. Restaure desde backup si fuera necesario."
}

Set-Content -Path $pagePath -Value $page -Encoding UTF8

# ----------------------------------------------------------------
# 4) CSS
# ----------------------------------------------------------------
if(-not (Test-Path $cssSource)){ throw "Falta table-single-invoices.css en el ZIP." }
Copy-Item $cssSource $cssTarget -Force

$layout = Get-Content $layoutPath -Raw
if($layout -notmatch 'table-single-invoices\.css'){
    if($layout -match 'import\s+"\./globals\.css";'){
        $layout = $layout -replace 'import\s+"\./globals\.css";', "import `"./globals.css`";`r`nimport `"./table-single-invoices.css`";"
    } elseif($layout -match "import\s+'\./globals\.css';"){
        $layout = $layout -replace "import\s+'\./globals\.css';", "import './globals.css';`r`nimport './table-single-invoices.css';"
    } else {
        $layout = "import `"./table-single-invoices.css`";`r`n" + $layout
    }
    Set-Content -Path $layoutPath -Value $layout -Encoding UTF8
    Write-Host "[OK] CSS V3 cargado." -ForegroundColor Green
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " LISTO: AHORA ES UNA SOLA TABLA REAL" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Facturas recibidas + pendientes comparten:" -ForegroundColor White
Write-Host "  - el mismo <table>" -ForegroundColor Green
Write-Host "  - el mismo tbody" -ForegroundColor Green
Write-Host "  - el mismo scroll horizontal" -ForegroundColor Green
Write-Host "  - el mismo scroll vertical" -ForegroundColor Green
Write-Host ""
Write-Host "Medidor y Servicio quedan fijos." -ForegroundColor White
Write-Host "La barra horizontal queda siempre en el bloque visible." -ForegroundColor White
Write-Host ""
Write-Host "Backup creado en:" -ForegroundColor Yellow
Write-Host "  $backup" -ForegroundColor White
Write-Host ""
Write-Host "Proba ahora con:" -ForegroundColor Cyan
Write-Host "  npm run dev" -ForegroundColor White
Write-Host ""
Read-Host "ENTER para cerrar"
