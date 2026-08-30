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

function Replace-RegexOnce {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    $rx = [regex]::new($Pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
    $matches = $rx.Matches($Text)
    if($matches.Count -lt 1){
        throw "No encontré el bloque esperado: $Label. No se aplicó el cambio."
    }
    return $rx.Replace($Text,$Replacement,1)
}

# =========================================================
# 1) DEPENDENCIAS / FACTURAS
# =========================================================
$invoiceText = Get-Content $invoice -Raw -Encoding UTF8

# Reemplaza únicamente el bloque de botones del gráfico, tolerando == o ===,
# espacios, saltos de línea y botones previos distintos.
$tabsPattern = '<div\s+className="invoice-analysis-metrics">.*?</div>'
$tabsReplacement = @'
<div className="invoice-analysis-metrics">
            <button className={metric==="demand"?"active":""} onClick={()=>setMetric("demand")}>Demanda</button>
            <button className={metric==="amount"?"active":""} onClick={()=>setMetric("amount")}>Importe</button>
            <button className={metric==="pf"?"active":""} onClick={()=>setMetric("pf")}>Factor de potencia</button>
            <button className={metric==="tariff"?"active":""} onClick={()=>setMetric("tariff")}>Tarifaria</button>
          </div>
'@
$invoiceText = Replace-RegexOnce $invoiceText $tabsPattern $tabsReplacement "pestañas del análisis individual"

# Asegura que abra por Demanda.
$metricPattern = 'const\s*\[\s*metric\s*,\s*setMetric\s*\]\s*=\s*useState<Metric>\(\s*"[^"]+"\s*\);'
$metricReplacement = 'const[metric,setMetric]=useState<Metric>("demand");'
$invoiceText = Replace-RegexOnce $invoiceText $metricPattern $metricReplacement "métrica inicial"

Set-Content $invoice -Value $invoiceText -Encoding UTF8

# =========================================================
# 2) ALUMBRADO PÚBLICO usa el MISMO análisis individual
# =========================================================
$publicText = Get-Content $public -Raw -Encoding UTF8

if($publicText -notmatch 'InvoiceAnalysisPanel'){
    $importPattern = 'import\s+type\s+\{\s*Session\s*\}\s+from\s+"@supabase/supabase-js";'
    $importReplacement = @'
import type { Session } from "@supabase/supabase-js";
import { InvoiceAnalysisPanel } from "./invoice-analysis-panel";
'@
    $publicText = Replace-RegexOnce $publicText $importPattern $importReplacement "import de InvoiceAnalysisPanel"
}

# Firma tolerante a espacios
$signaturePattern = 'export\s+function\s+PublicLightingPanel\s*\(\s*\{\s*session\s*,\s*organizationId\s*\}\s*:\s*\{\s*session\s*:\s*Session\s*;\s*organizationId\s*:\s*string\s*\}\s*\)\s*\{'
$signatureReplacement = 'export function PublicLightingPanel({session,organizationId,invoices,tariffSavings,epenOptimization}:{session:Session;organizationId:string;invoices:any[];tariffSavings:any[];epenOptimization:any[]}){'
if($publicText -match $signaturePattern){
    $publicText = Replace-RegexOnce $publicText $signaturePattern $signatureReplacement "firma de PublicLightingPanel"
} elseif($publicText -notmatch 'invoices:any\[\]'){
    throw "La firma de PublicLightingPanel es distinta a la esperada. No se aplicó el cambio."
}

if($publicText -notmatch 'const\s+selectedInvoice\s*='){
    $insertPattern = '(\s*if\s*\(\s*error\s*\)\s*return\s*<section\s+className="panel pl-error">)'
    $selectedBlock = @'
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

$1
'@
    $publicText = Replace-RegexOnce $publicText $insertPattern $selectedBlock "resolución de factura AP"
}

# Reemplaza la apertura vieja por el panel unificado.
$renderPattern = '\{selected\s*&&\s*<IndividualAnalysis\s+row=\{selected\}\s+onClose=\{\(\)=>setSelected\(null\)\}\s*/>\s*\}'
$renderReplacement = @'
{selected&&selectedInvoice&&<InvoiceAnalysisPanel
      invoice={selectedInvoice}
      history={invoices.filter(i=>i.meter_id===selectedInvoice.meter_id)}
      tariffSavings={tariffSavings}
      optimization={epenOptimization.find(x=>x.meter_id===selectedInvoice.meter_id)}
      onClose={()=>setSelected(null)}
    />}
    {selected&&!selectedInvoice&&<IndividualAnalysis row={selected} onClose={()=>setSelected(null)}/>}
'@
if($publicText -match $renderPattern){
    $publicText = Replace-RegexOnce $publicText $renderPattern $renderReplacement "apertura del análisis individual AP"
}

Set-Content $public -Value $publicText -Encoding UTF8

# =========================================================
# 3) PAGE: pasar datos al módulo AP
# =========================================================
$pageText = Get-Content $page -Raw -Encoding UTF8

# Busca la invocación autocerrada existente sin depender de espacios exactos.
$callPattern = '\{invoiceSubTab\s*==={0,1}\s*"publicLighting"\s*&&\s*<PublicLightingPanel\s+session=\{session\}\s+organizationId=\{orgId\|\|""\}\s*/>\s*\}'
$callReplacement = @'
{invoiceSubTab==="publicLighting"&&<PublicLightingPanel
  session={session}
  organizationId={orgId||""}
  invoices={invoices}
  tariffSavings={tariffSavings}
  epenOptimization={epenOptimization}
/>}
'@

if($pageText -match $callPattern){
    $pageText = Replace-RegexOnce $pageText $callPattern $callReplacement "llamada a PublicLightingPanel"
} elseif($pageText -notmatch '<PublicLightingPanel[\s\S]*?invoices=\{invoices\}'){
    # Variante muy flexible: cualquier invocación simple de PublicLightingPanel
    $callPattern2 = '\{invoiceSubTab\s*==={0,1}\s*"publicLighting"\s*&&\s*<PublicLightingPanel[\s\S]*?/>\s*\}'
    if($pageText -match $callPattern2){
        $pageText = Replace-RegexOnce $pageText $callPattern2 $callReplacement "llamada flexible a PublicLightingPanel"
    } else {
        throw "No encontré la llamada a PublicLightingPanel en page.tsx."
    }
}

Set-Content $page -Value $pageText -Encoding UTF8

Write-Host ""
Write-Host "ANALISIS UNIFICADO V2 aplicado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "Dependencias y Alumbrado Público quedan con el mismo análisis individual:" -ForegroundColor Cyan
Write-Host "  - Demanda"
Write-Host "  - Importe"
Write-Host "  - Factor de potencia"
Write-Host "  - Tarifaria"
Write-Host ""
Write-Host "Backups creados: .bak-$stamp"
Write-Host ""
Write-Host "Probar con:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
