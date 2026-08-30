$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$tsx = Join-Path $repo "front\app\public-lighting-panel.tsx"
$css = Join-Path $repo "front\app\public-lighting-panel.css"

foreach($file in @($tsx,$css)){
  if(-not (Test-Path $file)){
    throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
  }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $tsx "$tsx.bak-$stamp" -Force
Copy-Item $css "$css.bak-$stamp" -Force

# ============================================================
# 1) KPI superior: REQUIEREN REVISIÓN -> FACTURAS FALTANTES
# ============================================================
$text = Get-Content $tsx -Raw -Encoding UTF8

$oldKpi = @'
      <article className={data.summary.anomalies?"alert":""}>
        <span>REQUIEREN REVISIÓN</span>
        <strong>{data.summary.anomalies}</strong>
        <small>{data.summary.critical} críticas · {data.summary.warnings} alertas</small>
      </article>
'@

$newKpi = @'
      <article className={data.summary.missing?"alert":""}>
        <span>FACTURAS FALTANTES</span>
        <strong>{data.summary.missing}</strong>
        <small>sin factura en {data.billing_period}</small>
      </article>
'@

if(-not $text.Contains($oldKpi)){
  throw "No encontré el KPI REQUIEREN REVISIÓN esperado."
}
$text = $text.Replace($oldKpi,$newKpi)

# ============================================================
# 2) Fila sin factura: hacerlo explícito en Consumo e Importe
# ============================================================
$oldConsumption = '<b>{row.active_energy_kwh==null?"—":`${number.format(row.active_energy_kwh)} kWh`}</b>'
$newConsumption = '<b>{row.analysis_status==="missing"?"SIN FACTURA":row.active_energy_kwh==null?"—":`${number.format(row.active_energy_kwh)} kWh`}</b>'

if($text.Contains($oldConsumption)){
  $text = $text.Replace($oldConsumption,$newConsumption)
}

$oldAmount = '<span><b>{row.total_amount==null?"—":money.format(row.total_amount)}</b><small>facturado</small></span>'
$newAmount = '<span><b>{row.analysis_status==="missing"?"SIN FACTURA":row.total_amount==null?"—":money.format(row.total_amount)}</b><small>{row.analysis_status==="missing"?"faltante del período":"facturado"}</small></span>'

if($text.Contains($oldAmount)){
  $text = $text.Replace($oldAmount,$newAmount)
}

Set-Content $tsx -Value $text -Encoding UTF8

# ============================================================
# 3) CSS: filas faltantes en gris claramente visible
# ============================================================
$cssText = Get-Content $css -Raw -Encoding UTF8
$marker = "/* AP missing rows V11 */"

if($cssText -notmatch [regex]::Escape($marker)){
$extra = @'

/* AP missing rows V11 */
.pl-row.pl-data.missing{
  background:#eef1ef !important;
  color:#5f6d66;
}
.pl-row.pl-data.missing:hover{
  background:#e7ebe8 !important;
  box-shadow:inset 4px 0 #8d9a93;
}
.pl-row.pl-data.missing b{
  color:#56635d;
}
.pl-row.pl-data.missing small{
  color:#8a9690;
}
.pl-row.pl-data.missing .pl-status.missing{
  background:#dde3df;
  color:#66736d;
  font-weight:850;
}
'@
  $cssText += $extra
  Set-Content $css -Value $cssText -Encoding UTF8
}

Write-Host ""
Write-Host "AP FALTANTES + FILAS GRISES V11 aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Cambios:" -ForegroundColor Cyan
Write-Host "  - KPI 'Requieren revisión' reemplazado por 'Facturas faltantes'"
Write-Host "  - muestra data.summary.missing"
Write-Host "  - filas sin factura quedan grises"
Write-Host "  - Consumo e Importe muestran 'SIN FACTURA' en faltantes"
Write-Host ""
Write-Host "Backup creado con sufijo .bak-$stamp"
