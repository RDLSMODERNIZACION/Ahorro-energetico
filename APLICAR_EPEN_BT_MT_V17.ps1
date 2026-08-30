$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if ((Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Root "back\app\routers\tariff_history.py"))) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if ((Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) -and (Test-Path (Join-Path $Parent "back\app\routers\tariff_history.py"))) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$front=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$backend=Join-Path $Repo "back\app\routers\tariff_history.py"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_v17_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $front $backup
Copy-Item $backend $backup

Copy-Item (Join-Path $Root "payload\back\app\routers\tariff_history.py") $backend -Force

$f=Get-Content $front -Raw

# 1) Permitir mode mt en el tipo.
$f=$f.Replace(
  '  mode:"t4"|"none";',
  '  mode:"t4"|"mt"|"none";'
)

# 2) Agregar status/flags si no existen.
if($f -match 'type AdvancedTariffHistoryResponse=\{' -and $f -notmatch 'requires_epen_feasibility\?:boolean'){
  $f=[regex]::Replace(
    $f,
    '(type AdvancedTariffHistoryResponse=\{[\s\S]*?taxes_included\?:boolean;)',
    ('$1'+[Environment]::NewLine+'  status?:string;'+[Environment]::NewLine+'  requires_epen_feasibility?:boolean;'+[Environment]::NewLine+'  requires_epen_contract?:boolean;'),
    1
  )
}

# 3) Generalizar textos T4 específicos del detalle.
$f=$f.Replace(
  'Comparación entre lo realmente facturado y la tarifa T4 simulada del mismo período.',
  'Comparación entre lo realmente facturado y la tarifa propuesta simulada del mismo período.'
)
$f=$f.Replace(
  '<span>T4 SIMULADA</span>',
  '<span>TARIFA PROPUESTA SIMULADA</span>'
)
$f=$f.Replace(
  'Actual real facturada − T4 simulada · antes de impuestos',
  'Actual real facturada − tarifa propuesta simulada · antes de impuestos'
)
$f=$f.Replace(
  'Falta cuadro tarifario T4 para este período',
  'Falta cuadro tarifario oficial para este período'
)

# 4) Texto especial debajo de la fórmula para BT→MT.
$old='<small>Actual real facturada − tarifa propuesta simulada · antes de impuestos</small>'
$new='<small>Actual real facturada − tarifa propuesta simulada · antes de impuestos{advancedTariffHistory?.mode==="mt"?" · BT→MT sujeto a factibilidad EPEN":""}</small>'
if($f.Contains($old)){
  $f=$f.Replace($old,$new)
}

# 5) Mensaje de mes faltante genérico.
$f=$f.Replace(
  'Falta cuadro oficial {detail.recommended_tariff} para {periodOf(selected)}',
  'Falta cuadro oficial {detail.recommended_tariff} para {periodOf(selected)}'
)

Set-Content $front $f -Encoding UTF8

Write-Host ""
Write-Host "OK - V17 BT->MT aplicada." -ForegroundColor Green
Write-Host ""
Write-Host "Ahora Ahorro tarifario soporta:" -ForegroundColor Yellow
Write-Host "  - T3/T3A-BT real -> T3/T3A-MT simulada"
Write-Host "  - T3/T3A-MT real -> T4-MT simulada"
Write-Host "  - histórico hasta 24 meses"
Write-Host "  - detalle de conceptos y resolución"
Write-Host "  - resumen general mediante el mismo endpoint"
Write-Host ""
Write-Host "IMPORTANTE: desplegar backend en Render."
Write-Host "Backup: $backup"
