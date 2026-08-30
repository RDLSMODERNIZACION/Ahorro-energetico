param(
  [string]$Repo = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'

function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
  if(-not $Text.Contains($Old)){ throw "No encontré el bloque esperado: $Label. No hice ese cambio." }
  return $Text.Replace($Old,$New)
}

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$backRouter = Join-Path $Repo 'back\app\routers\public_lighting.py'
$frontPanel = Join-Path $Repo 'front\app\public-lighting-panel.tsx'
$mainPath = Join-Path $Repo 'back\app\main.py'
$pagePath = Join-Path $Repo 'front\app\page.tsx'
$cssPath = Join-Path $Repo 'front\app\globals.css'

if(!(Test-Path $mainPath)){ throw "No encuentro $mainPath" }
if(!(Test-Path $pagePath)){ throw "No encuentro $pagePath" }
if(!(Test-Path $cssPath)){ throw "No encuentro $cssPath" }

$sourceBackRouter = Join-Path $base 'back\app\routers\public_lighting.py'
$sourceFrontPanel = Join-Path $base 'front\app\public-lighting-panel.tsx'

# Si el ZIP fue descomprimido directamente sobre el repositorio, origen y destino
# pueden ser el mismo archivo. En ese caso no intentamos copiarlo sobre sí mismo.
if (([System.IO.Path]::GetFullPath($sourceBackRouter)) -ne ([System.IO.Path]::GetFullPath($backRouter))) {
  Copy-Item $sourceBackRouter $backRouter -Force
}
if (([System.IO.Path]::GetFullPath($sourceFrontPanel)) -ne ([System.IO.Path]::GetFullPath($frontPanel))) {
  Copy-Item $sourceFrontPanel $frontPanel -Force
}

$main = Get-Content $mainPath -Raw
if($main -notmatch 'public_lighting'){
  $main = Replace-Once $main `
    'from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization,tariff_history' `
    'from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence,epen_optimization,tariff_history,public_lighting' `
    'import public_lighting'
  $main = Replace-Once $main `
    'api.include_router(tariff_history.router,prefix="/api")' `
    "api.include_router(tariff_history.router,prefix=`"/api`")`r`napi.include_router(public_lighting.router,prefix=`"/api`")" `
    'include_router public_lighting'
  Set-Content $mainPath $main -Encoding UTF8
}

$page = Get-Content $pagePath -Raw

# Import del panel: tolera espacios / comillas simples o dobles.
if($page -notmatch 'PublicLightingPanel'){
  $importPattern = 'import\s*\{\s*MetersMap\s*\}\s*from\s*["'']\.\/meters-map["''];?'
  if($page -notmatch $importPattern){ throw "No encontré el import de MetersMap en page.tsx." }
  $page = [regex]::Replace(
    $page,
    $importPattern,
    '$0' + "`r`nimport { PublicLightingPanel } from `"./public-lighting-panel`";",
    1
  )
}

# Amplía el tipo de la subpestaña de Facturas, sin depender del formato exacto.
if($page -notmatch 'received"\|"missing"\|"publicLighting'){
  $statePattern = 'useState\s*<\s*["'']received["'']\s*\|\s*["'']missing["'']\s*>\s*\(\s*["'']received["'']\s*\)'
  if($page -match $statePattern){
    $page = [regex]::Replace($page,$statePattern,'useState<"received"|"missing"|"publicLighting">("received")',1)
  } elseif($page -notmatch 'publicLighting') {
    throw "No encontré el useState de invoiceSubTab para agregar publicLighting."
  }
}

# Inserta Alumbrado público inmediatamente después del botón Sin facturación reciente.
# Busca por el texto visible, así no depende de className, espacios o saltos de línea.
if($page -notmatch 'setInvoiceSubTab\(["'']publicLighting["'']\)'){
  $missingPattern = '(?s)(<button\b[^>]*>.*?<span>\s*Sin facturaci[oó]n reciente\s*</span>.*?</button>)'
  if($page -notmatch $missingPattern){ throw "No encontré el botón visible 'Sin facturación reciente' en page.tsx." }
  $lightingButton = @'
    <button className={invoiceSubTab==="publicLighting"?"active":""} onClick={()=>setInvoiceSubTab("publicLighting")}>
      <span>Alumbrado público</span>
      <b>AP</b>
    </button>
'@
  $page = [regex]::Replace($page,$missingPattern,'$1' + "`r`n" + $lightingButton,1)
}

# Inserta el contenido de la pestaña antes de que empiece tab="framing".
if($page -notmatch 'invoiceSubTab\s*===?\s*["'']publicLighting["'']\s*&&\s*<PublicLightingPanel'){
  $framingPattern = '(?=</>\}\{tab\s*===?\s*["'']framing["''])'
  if($page -notmatch $framingPattern){ throw "No encontré el cierre de Facturas antes de tab=framing." }
  $lightingPanel = '  {invoiceSubTab==="publicLighting"&&<PublicLightingPanel session={session} organizationId={orgId||""}/>}' + "`r`n"
  $page = [regex]::Replace($page,$framingPattern,$lightingPanel,1)
}

Set-Content $pagePath $page -Encoding UTF8

$css = Get-Content $cssPath -Raw
$marker = '/* ALUMBRADO PUBLICO V1 */'
if(-not $css.Contains($marker)){
$extra = @'

/* ALUMBRADO PUBLICO V1 */
.pl-module{display:grid;gap:14px}.pl-kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}.pl-kpis article{background:#fff;border:1px solid var(--line);border-radius:12px;padding:18px 20px}.pl-kpis span{display:block;font-size:9px;font-weight:800;color:#75847c;letter-spacing:.04em}.pl-kpis strong{display:block;margin-top:9px;font-size:23px}.pl-kpis small{display:block;margin-top:5px;color:#88968f;font-size:9px}.pl-kpis .green{background:#1b925e;border-color:#1b925e;color:#fff}.pl-kpis .green span,.pl-kpis .green small{color:#c9eedc}.pl-kpis .alert{background:#fff4f1;border-color:#efc8be}.pl-kpis .alert strong{color:#c84f3d}.pl-summary-strip{display:grid;grid-template-columns:repeat(4,1fr);padding:0}.pl-summary-strip>div{padding:16px 18px;border-right:1px solid var(--line)}.pl-summary-strip>div:last-child{border-right:0}.pl-summary-strip span{display:block;color:#78877f;font-size:9px}.pl-summary-strip b{display:block;margin-top:6px;font-size:15px}.pl-title{padding-bottom:15px}.pl-filters{display:flex;gap:12px;align-items:end;padding:14px 18px;background:#f8faf9;border-bottom:1px solid var(--line)}.pl-filters label{display:grid;gap:5px;color:#718078;font-size:9px;font-weight:800;text-transform:uppercase}.pl-filters select,.pl-filters input{height:37px;border:1px solid #dce5df;border-radius:7px;background:#fff;padding:0 10px;font:inherit;color:#24332c}.pl-filters .pl-search{flex:1}.pl-filters .pl-search input{width:100%}.pl-filters>button{height:37px;border:1px solid #d6e3dc;background:#fff;color:#2a7655;border-radius:7px;padding:0 14px;font-weight:750;cursor:pointer}.pl-table-scroll{overflow:auto;max-height:560px}.pl-table{min-width:1300px}.pl-row{display:grid;grid-template-columns:170px minmax(260px,1.5fr) 130px 125px 105px 145px 85px minmax(180px,1fr);align-items:center}.pl-head{position:sticky;top:0;z-index:3;background:#f8faf9;border-bottom:1px solid var(--line);padding:12px 15px;color:#74847b;font-size:8px;font-weight:850;letter-spacing:.04em}.pl-data{width:100%;border:0;border-bottom:1px solid #edf1ee;background:#fff;text-align:left;padding:13px 15px;cursor:pointer;color:inherit;font:inherit}.pl-data:hover{background:#f4faf7}.pl-data.warning{background:#fffdf8}.pl-data.critical{background:#fff8f6}.pl-data.missing{background:#fafbfa}.pl-data span{padding-right:12px;min-width:0}.pl-data b{display:block;font-size:10px;overflow:hidden;text-overflow:ellipsis}.pl-data small{display:block;margin-top:4px;color:#84918a;font-size:8px;overflow:hidden;text-overflow:ellipsis}.pl-danger{color:#c84f3d}.pl-tariff{display:inline-flex!important;width:auto;padding:5px 8px;border-radius:14px;background:#e8f6ef;color:#218259}.pl-tariff.review{background:#fff2df;color:#b8751d}.pl-status{display:inline-flex;padding:5px 8px;border-radius:6px;font-size:8px;font-style:normal;font-weight:850}.pl-status.normal{background:#eaf7f0;color:#238459}.pl-status.warning{background:#fff4df;color:#a96e19}.pl-status.critical{background:#fff0ed;color:#c64d3b}.pl-status.missing{background:#eff2f0;color:#76847d}.pl-empty,.pl-loading,.pl-error{padding:28px;text-align:center;color:#718078}.pl-error{color:#b94a3a}.pl-backdrop{position:fixed;inset:0;background:#10241c77;z-index:70;display:flex;justify-content:flex-end;backdrop-filter:blur(2px)}.pl-detail{width:min(720px,96vw);height:100%;overflow:auto;background:#f5f8f6;box-shadow:-20px 0 60px #081d1460}.pl-detail-head{padding:23px 26px;background:#173a2c;color:#fff;display:flex;justify-content:space-between;align-items:start}.pl-detail-head small{font-size:8px;color:#9bd1b8;letter-spacing:.12em}.pl-detail-head h2{font-size:20px;margin:7px 0}.pl-detail-head p{font-size:10px;color:#b1d2c3;margin:0}.pl-detail-head button{border:0;background:#ffffff18;color:#fff;width:34px;height:34px;border-radius:8px;font-size:23px;cursor:pointer}.pl-detail-kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;padding:16px}.pl-detail-kpis article{background:#fff;border:1px solid var(--line);border-radius:9px;padding:13px}.pl-detail-kpis article.alert{background:#fff4f1;border-color:#f0c3b9}.pl-detail-kpis span{display:block;font-size:8px;color:#78877f;margin-bottom:7px}.pl-detail-kpis b{font-size:13px}.pl-detail-section{margin:0 16px 14px;background:#fff;border:1px solid var(--line);border-radius:10px;overflow:hidden}.pl-detail-section h3{font-size:11px;margin:0;padding:13px 15px;border-bottom:1px solid var(--line)}.pl-detail-section ul,.pl-detail-section p{margin:0;padding:14px 30px;font-size:10px;line-height:1.55}.pl-history{max-height:390px;overflow:auto}.pl-history>div{display:grid;grid-template-columns:90px 1fr 1fr 70px;gap:12px;padding:10px 15px;border-bottom:1px solid #edf1ee;font-size:9px}.pl-history>div:last-child{border-bottom:0}.pl-history span:nth-child(3){text-align:right}.pl-history em{text-align:right;font-style:normal;color:#238459;font-weight:750}@media(max-width:1100px){.pl-kpis,.pl-summary-strip{grid-template-columns:repeat(2,1fr)}}
'@
  Add-Content $cssPath $extra -Encoding UTF8
}

Write-Host ''
Write-Host 'ALUMBRADO PUBLICO V1 aplicado.' -ForegroundColor Green
Write-Host '1) Backend: nuevo endpoint /api/organizations/{id}/public-lighting/analysis'
Write-Host '2) Front: nueva pestaña Alumbrado público dentro de Facturas'
Write-Host '3) Reiniciá backend y frontend / desplegá Render + Vercel.'
