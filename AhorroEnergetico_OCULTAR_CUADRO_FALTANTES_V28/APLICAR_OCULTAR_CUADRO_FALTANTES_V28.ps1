$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - OCULTAR CUADRO FALTANTES V28" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@(
  $here,
  (Join-Path $here "front"),
  (Split-Path -Parent $here),
  (Join-Path (Split-Path -Parent $here) "front")
) | Select-Object -Unique

$front=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))){
    $front=$c
    break
  }
}
if(-not $front){throw "No encontre front\app\page.tsx y globals.css."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White
Write-Host ""

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ocultar_cuadro_faltantes_v28_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw
$css=Get-Content $cssPath -Raw

# ------------------------------------------------------------------
# SOLO CSS: NO TOCA JSX.
# Detectamos clases relacionadas con el panel de faltantes y las ocultamos.
# ------------------------------------------------------------------
$candidateClasses = New-Object System.Collections.Generic.List[string]

# Buscar clases cerca de textos caracteristicos.
$markers=@(
  'Estos medidores no aparecen en el archivo del período seleccionado',
  'Faltan ',
  'facturas de ',
  'visibleMissingPeriodMeters'
)

foreach($marker in $markers){
  $idx=$page.IndexOf($marker)
  if($idx -ge 0){
    $from=[Math]::Max(0,$idx-1800)
    $length=[Math]::Min(3600,$page.Length-$from)
    $snippet=$page.Substring($from,$length)

    $matches=[regex]::Matches($snippet,'className="([^"]+)"')
    foreach($m in $matches){
      foreach($cls in $m.Groups[1].Value.Split(' ')){
        if($cls -match 'missing|falt|alert|period'){
          if(-not $candidateClasses.Contains($cls)){
            $candidateClasses.Add($cls)
          }
        }
      }
    }
  }
}

# Clases conocidas/posibles por los componentes previos.
$known=@(
  "missing-period-panel",
  "missing-period",
  "missing-invoices-panel",
  "missing-invoices",
  "missing-summary",
  "missing-cards",
  "missing-period-cards",
  "invoice-missing-summary-old"
)

foreach($k in $known){
  if($page -match [regex]::Escape($k)){
    if(-not $candidateClasses.Contains($k)){
      $candidateClasses.Add($k)
    }
  }
}

Write-Host "Clases detectadas relacionadas al cuadro:" -ForegroundColor Cyan
if($candidateClasses.Count){
  foreach($c in $candidateClasses){Write-Host "  .$c" -ForegroundColor Yellow}
}else{
  Write-Host "  No encontre una clase especifica." -ForegroundColor Yellow
}

# Si no detectamos clase, usamos :has() solo en navegadores modernos
# para ocultar un panel que contenga el texto/componente visual faltante.
$selectors = New-Object System.Collections.Generic.List[string]
foreach($c in $candidateClasses){
  $selectors.Add(".$c")
}

# Selectores fallback no destructivos.
$selectors.Add('.panel:has(.missing-card)')
$selectors.Add('.panel:has(.missing-invoice-card)')
$selectors.Add('.panel:has(.missing-alert-card)')

$uniqueSelectors=$selectors | Select-Object -Unique

# Remover bloque anterior.
$css=[regex]::Replace(
  $css,
  '(?s)/\* === OCULTAR CUADRO FALTANTES V28 START === \*/.*?/\* === OCULTAR CUADRO FALTANTES V28 END === \*/',
  ''
)

$selectorText=($uniqueSelectors -join ",`r`n")

$block=@"

/* === OCULTAR CUADRO FALTANTES V28 START === */
/*
  Este fix es SOLO visual.
  No modifica page.tsx ni la estructura JSX.
  Los faltantes siguen disponibles en la subpestaña "Sin factura".
*/
$selectorText {
  display:none !important;
}
/* === OCULTAR CUADRO FALTANTES V28 END === */
"@

$css=$css.TrimEnd()+"`r`n`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# Limpiar cache Vite
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificacion: page.tsx debe quedar byte-a-byte igual al backup.
$currentHash=(Get-FileHash $pagePath -Algorithm SHA256).Hash
$backupHash=(Get-FileHash (Join-Path $backup "page.tsx") -Algorithm SHA256).Hash
$jsxUntouched=$currentHash -eq $backupHash
$cssOk=(Get-Content $cssPath -Raw) -match 'OCULTAR CUADRO FALTANTES V28 START'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  JSX sin tocar: $jsxUntouched"
Write-Host "  CSS aplicado: $cssOk"

if(-not ($jsxUntouched -and $cssOk)){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V28 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Este fix NO toca page.tsx." -ForegroundColor Green
Write-Host "Solo oculta visualmente el cuadro redundante de faltantes." -ForegroundColor Green
Write-Host ""
Write-Host "Los faltantes siguen en la subpestana 'Sin factura'." -ForegroundColor White
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
