$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - NOMBRES FALTANTES V32" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$front=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "app\page.tsx")) -and (Test-Path (Join-Path $c "app\globals.css"))){
    $front=$c;break
  }
}
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_nombres_faltantes_v32_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

# Subpestaña
$page=$page.Replace('<span>Sin factura</span>','<span>Sin facturación reciente</span>')

# KPI / etiquetas principales
$page=$page.Replace('<span>Facturas faltantes</span>','<span>Faltantes de agosto</span>')
$page=$page.Replace('<span>Facturas faltantes</span>','<span>Faltantes del período</span>')

# Encabezado de la vista secundaria
$page=$page.Replace('MEDIDORES SIN FACTURA','POSIBLES BAJAS / SIN FACTURACIÓN RECIENTE')
$page=$page.Replace('Medidores sin factura','Sin facturación reciente')
$page=$page.Replace('Seguimiento separado','Posibles bajas y medidores sin facturación reciente')
$page=$page.Replace(
  'Acá se muestran únicamente los medidores que no tienen facturación reciente o están en posible baja.',
  'Acá se muestran los medidores que llevan varios meses sin facturación y requieren definir si continúan activos o corresponden a una baja.'
)

# Contadores y textos
$page=$page.Replace('medidores en seguimiento','posibles bajas / seguimiento')
$page=$page.Replace('Facturas faltantes','Faltantes del período')

Set-Content $pagePath $page -Encoding UTF8

foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
$ok1=$check -match 'Sin facturación reciente'
$ok2=$check -match 'POSIBLES BAJAS / SIN FACTURACIÓN RECIENTE'

if(-not ($ok1 -and $ok2)){throw "La verificacion final fallo."}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V32 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora queda mas claro:" -ForegroundColor White
Write-Host " - Facturas recibidas" -ForegroundColor Green
Write-Host " - Faltantes del periodo" -ForegroundColor Green
Write-Host " - Sin facturacion reciente / posibles bajas" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
