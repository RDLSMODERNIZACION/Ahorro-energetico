$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo = $null
if ((Test-Path (Join-Path $Root "front\app\page.tsx")) -and (Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx"))) {
  $Repo = $Root
} else {
  $Parent = (Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\page.tsx")) -and (Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx"))) {
    $Repo = $Parent
  }
}
if (-not $Repo) { throw "No encontré la raíz de Ahorro-energetico." }

$epenPanel = Join-Path $Repo "front\app\epen-optimization-panel.tsx"
$epenBackend = Join-Path $Repo "back\app\routers\epen_optimization.py"
if (-not (Test-Path $epenPanel) -or -not (Test-Path $epenBackend)) {
  throw "Primero aplicá EPEN_OPTIMIZACION_V1_FIX. No encuentro los archivos de la V1."
}

Write-Host "Repositorio detectado: $Repo" -ForegroundColor Cyan

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
@(
  "front\app\page.tsx",
  "front\app\invoice-analysis-panel.tsx",
  "front\app\epen-optimization-panel.tsx",
  "front\app\globals.css",
  "back\app\routers\epen_optimization.py"
) | ForEach-Object { Copy-Item (Join-Path $Repo $_) $backup }

# -------------------------------------------------------------------
# 1) Exportar tipos desde epen-optimization-panel.tsx
# -------------------------------------------------------------------
$p=Get-Content $epenPanel -Raw
if ($p -notmatch "export type EpenOptimizationMeter") {
  $p=$p.Replace("type Row = {", "export type EpenOptimizationMeter = {")
  $p=$p.Replace("type Response = {", "export type EpenOptimizationResponse = {")
  $p=$p.Replace("meters:Row[];", "meters:EpenOptimizationMeter[];")
  $p=$p.Replace("Promise<Response>", "Promise<EpenOptimizationResponse>")
  $p=$p.Replace("useState<Response|null>", "useState<EpenOptimizationResponse|null>")
  Set-Content $epenPanel $p -Encoding UTF8
}

# -------------------------------------------------------------------
# 2) Endpoint individual por medidor
# -------------------------------------------------------------------
$backend=Get-Content $epenBackend -Raw
if ($backend -notmatch 'meters/\{meter_id\}/epen-optimization') {
$append=@'

@router.get("/meters/{meter_id}/epen-optimization")
def meter_epen_optimization(meter_id: str, user: CurrentUser = Depends(current_user)):
    """Devuelve el diagnóstico EPEN avanzado de un solo medidor."""
    db = admin_db()
    meter_rows = db.table("meters").select("id,organization_id").eq("id", meter_id).limit(1).execute().data or []
    if not meter_rows:
        return {"meter": None}
    organization_id = meter_rows[0]["organization_id"]
    require_org(user.id, organization_id)
    result = epen_optimization(organization_id, user)
    row = next((x for x in result.get("meters", []) if x.get("meter_id") == meter_id), None)
    return {"meter": row, "period": result.get("period"), "taxes_included": False}
'@
  Add-Content $epenBackend $append -Encoding UTF8
}

# -------------------------------------------------------------------
# 3) page.tsx: cargar optimización y pasarla a tabla + análisis individual
# -------------------------------------------------------------------
$pagePath=Join-Path $Repo "front\app\page.tsx"
$page=Get-Content $pagePath -Raw

$oldImport='import { EpenOptimizationPanel } from "./epen-optimization-panel";'
$newImport='import { EpenOptimizationPanel, type EpenOptimizationMeter, type EpenOptimizationResponse } from "./epen-optimization-panel";'
if ($page.Contains($oldImport)) {$page=$page.Replace($oldImport,$newImport)}

if ($page -notmatch 'setEpenOptimization') {
  $needle='const[session,setSession]=useState<Session|null>(null),[authReady,setAuthReady]=useState(false);'
  if (-not $page.Contains($needle)) { throw "No encontré el inicio del estado principal en page.tsx." }
  $replacement=$needle + "`r`n  const[epenOptimization,setEpenOptimization]=useState<EpenOptimizationMeter[]>([]);"
  $page=$page.Replace($needle,$replacement)

  $needle2='setMissing(miss);setAssessments(frames);setTariffSavings(tariffResult?.candidates||[]);'
  if (-not $page.Contains($needle2)) { throw "No encontré el bloque de carga de tariffSavings en page.tsx." }
  $replacement2=$needle2 + 'const epen=await api<EpenOptimizationResponse>(`/api/organizations/${target}/epen-optimization?v=2`,s).catch(()=>null);setEpenOptimization(epen?.meters||[]);'
  $page=$page.Replace($needle2,$replacement2)
}

# Agregar optimization a InvoiceAnalysisPanel (todas las ocurrencias)
$page=$page.Replace('tariffSavings={tariffSavings} onClose={()=>setSelectedInvoice(null)}/>', 'tariffSavings={tariffSavings} optimization={epenOptimization.find(x=>x.meter_id===selectedInvoice.meter_id)} onClose={()=>setSelectedInvoice(null)}/>')

# Pasar optimización a InvoiceTable
$page=$page.Replace('tariffSavings={tariffSavings} pendingMeters={visibleMissingPeriodMeters}', 'tariffSavings={tariffSavings} epenOptimization={epenOptimization} pendingMeters={visibleMissingPeriodMeters}')

# Firma InvoiceTable
$oldSig='function InvoiceTable({invoices,assessments,tariffSavings,pendingMeters,period,onSelect}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];pendingMeters:Meter[];period:string;onSelect?:(i:Invoice)=>void})'
$newSig='function InvoiceTable({invoices,assessments,tariffSavings,epenOptimization,pendingMeters,period,onSelect}:{invoices:Invoice[];assessments:TariffAssessment[];tariffSavings:TariffSaving[];epenOptimization:EpenOptimizationMeter[];pendingMeters:Meter[];period:string;onSelect?:(i:Invoice)=>void})'
if ($page.Contains($oldSig)) {$page=$page.Replace($oldSig,$newSig)}

# Dentro de map, sumar advanced
$needle3='candidate=assessments.find(a=>a.meter_id===i.meter_id),assessment='
if ($page.Contains($needle3) -and $page -notmatch 'advanced=epenOptimization.find') {
  $page=$page.Replace($needle3,'advanced=epenOptimization.find(e=>e.meter_id===i.meter_id),candidate=assessments.find(a=>a.meter_id===i.meter_id),assessment=')
}

# Reemplazar celda Tarifa por versión con alertas avanzadas
$oldCell='<td><span className="tag low">{i.current_tariff_code||"S/D"}</span><small>{tariffResult&&tariffResult.current_tariff!==tariffResult.recommended_tariff?<>{tariffResult.current_tariff} → {tariffResult.recommended_tariff}</>:(i.voltage_level||i.meters?.voltage_level)}</small></td>'
$newCell=@'
<td><div className="tariff-advanced-cell"><div><span className="tag low">{i.current_tariff_code||"S/D"}</span><small>{tariffResult&&tariffResult.current_tariff!==tariffResult.recommended_tariff?<>{tariffResult.current_tariff} → {tariffResult.recommended_tariff}</>:(i.voltage_level||i.meters?.voltage_level)}</small></div>{advanced&&<div className="tariff-advanced-badges">{advanced.t3.status==="candidate"&&<span className="t3-dual">T3 · 2 POTENCIAS</span>}{advanced.t4.status==="candidate"&&<span className="t4-candidate">APTO T4</span>}{["strong","candidate","preliminary"].includes(advanced.mt.status)&&<span className="mt-candidate">BT → MT</span>}</div>}</div></td>
'@
if ($page.Contains($oldCell)) {$page=$page.Replace($oldCell,$newCell)}

Set-Content $pagePath $page -Encoding UTF8

# -------------------------------------------------------------------
# 4) invoice-analysis-panel.tsx
# -------------------------------------------------------------------
$invoicePath=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$inv=Get-Content $invoicePath -Raw
if ($inv -notmatch 'EpenOptimizationMeter') {
  $inv=$inv.Replace('import { supabase } from "./lib/supabase";','import { supabase } from "./lib/supabase";'+"`r`n"+'import type { EpenOptimizationMeter } from "./epen-optimization-panel";')
}

$oldProp='export function InvoiceAnalysisPanel({invoice,history,tariffSavings,onClose}:{invoice:Invoice;history:Invoice[];tariffSavings:TariffSaving[];onClose:()=>void})'
$newProp='export function InvoiceAnalysisPanel({invoice,history,tariffSavings,optimization,onClose}:{invoice:Invoice;history:Invoice[];tariffSavings:TariffSaving[];optimization?:EpenOptimizationMeter;onClose:()=>void})'
if ($inv.Contains($oldProp)) {$inv=$inv.Replace($oldProp,$newProp)}

if ($inv -notmatch 'ANÁLISIS TARIFARIO AVANZADO EPEN') {
$marker='      <section className="invoice-analysis-panel">'+"`r`n"+'        <div className="invoice-analysis-chart-head">'
$block=@'
      {optimization&&<section className="invoice-analysis-panel epen-individual-analysis">
        <div className="epen-individual-head">
          <div><span>ANÁLISIS TARIFARIO AVANZADO EPEN</span><h3>T3 · T4 · Nivel de tensión</h3><p>Oportunidades adicionales calculadas con el cuadro tarifario del período. Valores antes de impuestos.</p></div>
        </div>
        <div className="epen-individual-grid">
          <article className={optimization.t3.status==="candidate"?"candidate":""}>
            <span>T3 · Potencia por franja</span>
            <b>{optimization.current_tariff==="T3"||optimization.current_tariff==="T3A"?"Punta / fuera punta":"No aplica"}</b>
            {(optimization.current_tariff==="T3"||optimization.current_tariff==="T3A")&&<>
              <small>Actual: {nf.format(optimization.t3.current_peak_kw)} / {nf.format(optimization.t3.current_off_peak_kw)} kW</small>
              <small>Máx. 12m: {nf.format(optimization.t3.max_registered_peak_12m_kw)} / {nf.format(optimization.t3.max_registered_off_peak_12m_kw)} kW</small>
              <strong>{optimization.t3.monthly_saving_before_taxes!=null?`${money.format(optimization.t3.monthly_saving_before_taxes)}/mes`:"Faltan datos por franja"}</strong>
            </>}
          </article>
          <article className={optimization.t4.status==="candidate"?"candidate":""}>
            <span>Cambio T3 → T4</span>
            <b>{optimization.t4.status==="candidate"?`Candidato ${optimization.t4.target_tariff||"T4"}`:optimization.t4.status==="requires_mt"?"Requiere MT":optimization.t4.status==="insufficient_history"?"Falta historial":"No elegible aún"}</b>
            <small>{optimization.t4.months_over_100kw_last12}/12 meses con demanda ≥100 kW</small>
            {optimization.t4.t4_cost_before_taxes!=null&&<small>T4 simulado: {money.format(Number(optimization.t4.t4_cost_before_taxes))}</small>}
            <strong>{optimization.t4.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.t4.monthly_saving_before_taxes))}/mes`:"Requiere validación"}</strong>
          </article>
          <article className={["strong","candidate","preliminary"].includes(optimization.mt.status)?"candidate":""}>
            <span>Baja Tensión → Media Tensión</span>
            <b>{optimization.mt.status==="strong"?"Candidato fuerte":optimization.mt.status==="candidate"?"Candidato":optimization.mt.status==="preliminary"?"Estudio preliminar":"No prioritario"}</b>
            <small>Máxima 12m: {nf.format(optimization.max_demand_12m_kw)} kW</small>
            {optimization.mt.simulated_mt_cost_before_taxes!=null&&<small>MT simulado: {money.format(Number(optimization.mt.simulated_mt_cost_before_taxes))}</small>}
            <strong>{optimization.mt.monthly_saving_before_taxes!=null?`${money.format(Number(optimization.mt.monthly_saving_before_taxes))}/mes`:"Requiere factibilidad EPEN"}</strong>
          </article>
        </div>
      </section>}

'@
if (-not $inv.Contains($marker)) { throw "No encontré el gráfico histórico en invoice-analysis-panel.tsx." }
$inv=$inv.Replace($marker,$block+$marker)
}

Set-Content $invoicePath $inv -Encoding UTF8

# -------------------------------------------------------------------
# 5) CSS
# -------------------------------------------------------------------
$cssPath=Join-Path $Repo "front\app\globals.css"
$css=Get-Content $cssPath -Raw
if ($css -notmatch 'EPEN ADVANCED V2') {
$styles=@'

/* EPEN ADVANCED V2 */
.tariff-advanced-cell{display:flex;align-items:flex-start;gap:8px;flex-wrap:wrap}
.tariff-advanced-cell>div:first-child{display:grid;gap:3px}
.tariff-advanced-badges{display:flex;gap:4px;flex-wrap:wrap;max-width:180px}
.tariff-advanced-badges span{display:inline-flex;align-items:center;white-space:nowrap;border-radius:999px;padding:4px 7px;font-size:9px;font-weight:900;letter-spacing:.02em}
.tariff-advanced-badges .t3-dual{background:#eff6ff;color:#1d4ed8;border:1px solid #bfdbfe}
.tariff-advanced-badges .t4-candidate{background:#ecfdf5;color:#047857;border:1px solid #a7f3d0}
.tariff-advanced-badges .mt-candidate{background:#fff7ed;color:#c2410c;border:1px solid #fed7aa}
.epen-individual-analysis{border:1px solid #cbd5e1!important;background:linear-gradient(180deg,#fff 0%,#f8fafc 100%)!important}
.epen-individual-head span{font-size:10px;font-weight:900;letter-spacing:.12em;color:#047857}
.epen-individual-head h3{margin:4px 0 3px!important}
.epen-individual-head p{margin:0;color:#64748b;font-size:12px}
.epen-individual-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-top:16px}
.epen-individual-grid article{display:grid;align-content:start;gap:6px;min-height:150px;padding:15px;border:1px solid #e2e8f0;border-radius:14px;background:#fff}
.epen-individual-grid article.candidate{border-color:#86efac;background:#f0fdf4}
.epen-individual-grid article>span{font-size:11px;font-weight:900;color:#64748b;text-transform:uppercase}
.epen-individual-grid article>b{font-size:16px;color:#0f172a}
.epen-individual-grid article>small{font-size:11px;color:#64748b}
.epen-individual-grid article>strong{margin-top:auto;font-size:16px;color:#047857}
@media(max-width:1000px){.epen-individual-grid{grid-template-columns:1fr}}
'@
Add-Content $cssPath $styles -Encoding UTF8
}

Write-Host ""
Write-Host "OK - EPEN Optimización V2 instalada." -ForegroundColor Green
Write-Host "Ahora aparece:" -ForegroundColor Yellow
Write-Host "  1. En la columna TARIFA de Facturas: T3 2 POTENCIAS / APTO T4 / BT->MT"
Write-Host "  2. Dentro del análisis individual de cada factura: bloque T3 / T4 / BT->MT"
Write-Host "Backup: $backup"
