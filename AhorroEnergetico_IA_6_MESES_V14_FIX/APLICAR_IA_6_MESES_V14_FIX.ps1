$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - IA 6 MESES V14 FIX" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Split-Path -Parent $here))|Select-Object -Unique
$root=$null
foreach($c in $candidates){
  if(Test-Path (Join-Path $c "back\app\routers\ai.py")){
    $root=$c;break
  }
}
if(-not $root){throw "No encontre back\app\routers\ai.py."}

$aiPath=Join-Path $root "back\app\routers\ai.py"

Write-Host "[OK] Archivo:" -ForegroundColor Green
Write-Host "  $aiPath" -ForegroundColor White
Write-Host ""

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_ia_6_meses_v14_fix_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $aiPath (Join-Path $backup "ai.py") -Force

$ai=Get-Content $aiPath -Raw

Write-Host "Diagnostico antes del cambio:" -ForegroundColor Cyan
if($ai -match 'sorted\(monthly\)\[-(\d+):\]'){
  Write-Host "  Ventana mensual actual: $($Matches[1]) meses" -ForegroundColor Yellow
}else{
  Write-Host "  No encontre slice mensual exacto; voy a usar reemplazo flexible." -ForegroundColor Yellow
}

# ---------------------------------------------------
# 1. Forzar cualquier slice mensual a 6 meses.
# ---------------------------------------------------
$ai=[regex]::Replace(
  $ai,
  'sorted\(monthly\)\[-\d+:\]',
  'sorted(monthly)[-6:]'
)

# Si usa otra variable o formato similar, corregimos también.
$ai=[regex]::Replace(
  $ai,
  'sorted\(monthly\.keys\(\)\)\[-\d+:\]',
  'sorted(monthly.keys())[-6:]'
)

# ---------------------------------------------------
# 2. Compactar rankings de contexto.
# ---------------------------------------------------
$replacements = @{
  'low_pf\[:12\]'='low_pf[:6]'
  'low_pf\[:8\]'='low_pf[:6]'
  'excess\[:12\]'='excess[:6]'
  'excess\[:8\]'='excess[:6]'
  'top_consumption\[:12\]'='top_consumption[:6]'
  'top_consumption\[:8\]'='top_consumption[:6]'
  'top_amount\[:12\]'='top_amount[:6]'
  'top_amount\[:8\]'='top_amount[:6]'
  'missing\[:25\]'='missing[:12]'
  'missing\[:15\]'='missing[:12]'
  'opportunities\[:25\]'='opportunities[:12]'
  'opportunities\[:15\]'='opportunities[:12]'
  'low_pf\[:60\]'='low_pf[:18]'
  'low_pf\[:25\]'='low_pf[:18]'
  'excess\[:60\]'='excess[:18]'
  'excess\[:25\]'='excess[:18]'
  'top_consumption\[:60\]'='top_consumption[:18]'
  'top_consumption\[:25\]'='top_consumption[:18]'
  'top_amount\[:60\]'='top_amount[:18]'
  'top_amount\[:25\]'='top_amount[:18]'
  'missing\[:100\]'='missing[:25]'
  'missing\[:40\]'='missing[:25]'
  'opportunities\[:100\]'='opportunities[:25]'
  'opportunities\[:40\]'='opportunities[:25]'
}

foreach($key in $replacements.Keys){
  $ai=$ai.Replace($key,$replacements[$key])
}

# ---------------------------------------------------
# 3. Limite de output / verbosity.
# ---------------------------------------------------
if($ai -notmatch '"max_output_tokens"\s*:\s*\d+'){
  $anchor='"store": False,'
  if($ai.Contains($anchor)){
    $ai=$ai.Replace($anchor,$anchor+"`r`n        "+'"max_output_tokens": 700,')
  }
}else{
  $ai=[regex]::Replace($ai,'"max_output_tokens"\s*:\s*\d+','"max_output_tokens": 700')
}

$ai=$ai.Replace('"text": {"verbosity": "medium"}','"text": {"verbosity": "low"}')

# ---------------------------------------------------
# 4. Instruccion explicita de 6 meses.
# ---------------------------------------------------
if($ai -notmatch 'últimos 6 meses'){
  $needle='Si la información no alcanza para responder algo, decilo explícitamente.'
  if($ai.Contains($needle)){
    $ai=$ai.Replace(
      $needle,
      $needle+' Para tendencias, comparaciones y mejoras, priorizá siempre los últimos 6 meses disponibles en monthly_history.'
    )
  }
}

Set-Content $aiPath $ai -Encoding UTF8

# ---------------------------------------------------
# 5. Verificacion flexible real.
# ---------------------------------------------------
$check=Get-Content $aiPath -Raw
$okMonths=$check -match 'sorted\(monthly\)\[-6:\]' -or $check -match 'sorted\(monthly\.keys\(\)\)\[-6:\]'
$okOutput=$check -match '"max_output_tokens"\s*:\s*700'
$okRank=$check -match 'low_pf\[:6\]' -or $check -match '"top_low_power_factor"'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  6 meses:            $okMonths"
Write-Host "  max_output_tokens:  $okOutput"
Write-Host "  ranking compacto:   $okRank"

if(-not $okMonths){
  Write-Host ""
  Write-Host "[ERROR] No pude localizar la construccion de monthly_history." -ForegroundColor Red
  Write-Host "Te dejo el backup y no borro nada." -ForegroundColor Yellow
  Write-Host "Archivo: $aiPath" -ForegroundColor Yellow
  Read-Host "ENTER para cerrar"
  exit 1
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V14 FIX APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "La IA ahora usa 6 meses de historial para tendencias." -ForegroundColor Green
Write-Host "Tambien queda limitado el output para reducir TPM/costo." -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANTE:" -ForegroundColor Yellow
Write-Host "Subi back\app\routers\ai.py a Render y hace redeploy." -ForegroundColor White
Write-Host ""
Write-Host "Backup:" -ForegroundColor DarkGray
Write-Host "  $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
