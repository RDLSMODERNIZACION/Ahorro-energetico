$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$page = Join-Path $repo "front\app\page.tsx"
$invoice = Join-Path $repo "front\app\invoice-analysis-panel.tsx"
$public = Join-Path $repo "front\app\public-lighting-panel.tsx"

foreach($file in @($page,$invoice,$public)){
    if(-not (Test-Path $file)){
        throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $page "$page.bak-$stamp" -Force
Copy-Item $invoice "$invoice.bak-$stamp" -Force
Copy-Item $public "$public.bak-$stamp" -Force

function Replace-Once {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label
    )
    if(-not $Text.Contains($Old)){
        throw "No encontré el bloque esperado: $Label. No se aplicó el cambio."
    }
    return $Text.Replace($Old,$New)
}

# =========================================================
# 1) DEPENDENCIAS / FACTURAS:
#    Restaurar Demanda + Importe + Factor de potencia + Tarifaria
# =========================================================
$invoiceText = Get-Content $invoice -Raw -Encoding UTF8

$oldTabs = @'
          <div className="invoice-analysis-metrics">
            <button className={metric==="demand"?"active":""} onClick={()=>setMetric("demand")}>Demanda</button>
            <button className={metric==="amount"?"active":""} onClick={()=>setMetric("amount")}>Importe</button>
          </div>
'@

$newTabs = @'
          <div className="invoice-analysis-metrics">
            <button className={metric==="demand"?"active":""} onClick={()=>setMetric("demand")}>Demanda</button>
            <button className={metric==="amount"?"active":""} onClick={()=>setMetric("amount")}>Importe</button>
            <button className={metric==="pf"?"active":""} onClick={()=>setMetric("pf")}>Factor de potencia</button>
            <button className={metric==="tariff"?"active":""} onClick={()=>setMetric("tariff")}>Tarifaria</button>
          </div>
'@

$invoiceText = Replace-Once $invoiceText $oldTabs $newTabs "pestañas del análisis individual"
Set-Content $invoice -Value $invoiceText -Encoding UTF8

# =========================================================
# 2) ALUMBRADO PÚBLICO:
#    Reutilizar EXACTAMENTE el mismo InvoiceAnalysisPanel
#    que usan las dependencias cuando existe la factura.
#    Si por algún motivo no puede mapear la factura, mantiene
#    el análisis AP anterior como respaldo.
# =========================================================
$publicText = Get-Content $public -Raw -Encoding UTF8

$oldImport = 'import type { Session } from "@supabase/supabase-js";'
$newImport = @'
import type { Session } from "@supabase/supabase-js";
import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";
'@
$publicText = Replace-Once $publicText $oldImport $newImport "import de InvoiceAnalysisPanel"

$oldSignature = 'export function PublicLightingPanel({session,organizationId}:{session:Session;organizationId:string}){'
$newSignature = 'export function PublicLightingPanel({session,organizationId,invoices,tariffSavings,epenOptimization}:{session:Session;organizationId:string;invoices:any[];tariffSavings:any[];epenOptimization:any[]}){'
$publicText = Replace-Once $publicText $oldSignature $newSignature "firma de PublicLightingPanel"

$marker = '  if(error)return <section className="panel pl-error">{error}</section>;'
$selectedInvoiceBlock = @'
  const selectedInvoice=selected?(
    (selected.invoice_id?invoices.find(i=>String(i.id)===String(selected.invoice_id)):undefined)
    ||invoices.find(i=>
      String(i.invoice_number||"")===String(selected.invoice_number||"")
      &&String(i.billing_period||i.period_start||"").slice(0,7)===String(selected.billing_period||"").slice(0,7)
    )
    ||invoices.find(i=>
      (
        String(i.meters?.meter_number||"")===String(selected.meter_number||"")
        ||String(i.meters?.supply_number||"")===String(selected.supply_number||"")
      )
      &&String(i.billing_period||i.period_start||"").slice(0,7)===String(selected.billing_period||"").slice(0,7)
    )
  ):null;

'@ + $marker
$publicText = Replace-Once $publicText $marker $selectedInvoiceBlock "resolución de factura de Alumbrado Público"

$oldRender = '    {selected&&<IndividualAnalysis row={selected} onClose={()=>setSelected(null)}/>}'

$newRender = @'
    {selected&&selectedInvoice&&<InvoiceAnalysisPanel
      invoice={selectedInvoice}
      history={invoices.filter(i=>i.meter_id===selectedInvoice.meter_id)}
      tariffSavings={tariffSavings}
      optimization={epenOptimization.find(x=>x.meter_id===selectedInvoice.meter_id)}
      onClose={()=>setSelected(null)}
    />}
    {selected&&!selectedInvoice&&<IndividualAnalysis row={selected} onClose={()=>setSelected(null)}/>}
'@
$publicText = Replace-Once $publicText $oldRender $newRender "apertura del análisis individual de Alumbrado Público"
Set-Content $public -Value $publicText -Encoding UTF8

# =========================================================
# 3) PAGE:
#    Pasar a Alumbrado Público la misma información usada
#    por el análisis individual de dependencias.
# =========================================================
$pageText = Get-Content $page -Raw -Encoding UTF8

$oldCall = '{invoiceSubTab==="publicLighting"&&<PublicLightingPanel session={session} organizationId={orgId||""}/>}'

$newCall = @'
{invoiceSubTab==="publicLighting"&&<PublicLightingPanel
  session={session}
  organizationId={orgId||""}
  invoices={invoices}
  tariffSavings={tariffSavings}
  epenOptimization={epenOptimization}
/>}
'@

$pageText = Replace-Once $pageText $oldCall $newCall "llamada a PublicLightingPanel"
Set-Content $page -Value $pageText -Encoding UTF8

Write-Host ""
Write-Host "ANALISIS UNIFICADO V1 aplicado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "Resultado:" -ForegroundColor Cyan
Write-Host "  - Dependencias: Demanda / Importe / Factor de potencia / Tarifaria"
Write-Host "  - Alumbrado Público: abre el MISMO análisis individual que Dependencias"
Write-Host "  - Si una fila AP no puede vincularse con su factura, usa el análisis AP anterior como respaldo"
Write-Host ""
Write-Host "Se crearon copias .bak-$stamp de los 3 archivos modificados."
Write-Host ""
Write-Host "Para probar:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
