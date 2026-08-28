$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - CAPA ANALITICA IA V47" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$root=$null
foreach($c in @($here,(Split-Path -Parent $here))){
  if((Test-Path (Join-Path $c "back\app\main.py")) -and
     (Test-Path (Join-Path $c "back\app\routers\ai.py"))){$root=$c;break}
}
if(-not $root){throw "No encontre el proyecto."}

$pkg=Split-Path -Parent $MyInvocation.MyCommand.Path
$payload=Join-Path $pkg "payload"
$back=Join-Path $root "back\app"
$routers=Join-Path $back "routers"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_capa_analitica_v47_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null

foreach($f in @(
  (Join-Path $back "main.py"),
  (Join-Path $routers "ai.py"),
  (Join-Path $routers "imports.py")
)){
  if(Test-Path $f){Copy-Item $f $backup -Force}
}

Copy-Item (Join-Path $payload "energy_intelligence.py") (Join-Path $back "energy_intelligence.py") -Force
Copy-Item (Join-Path $payload "intelligence.py") (Join-Path $routers "intelligence.py") -Force

# MAIN: registrar router
$mainPath=Join-Path $back "main.py"
$main=Get-Content $mainPath -Raw
if($main -notmatch 'intelligence'){
  $main=$main.Replace(
    'from .routers import analysis,catalog,imports,invoices,tariffs,ai,ai',
    'from .routers import analysis,catalog,imports,invoices,tariffs,ai,intelligence'
  )
  if($main -notmatch 'include_router\(intelligence\.router'){
    $main=$main.Replace(
      'api.include_router(ai.router,prefix="/api")',
      'api.include_router(ai.router,prefix="/api")'+"`r`n"+'api.include_router(intelligence.router,prefix="/api")'
    )
  }
}
Set-Content $mainPath $main -Encoding UTF8

# IMPORTS: refresco en background después de cada carga
$importsPath=Join-Path $routers "imports.py"
$imports=Get-Content $importsPath -Raw
if($imports -notmatch 'BackgroundTasks'){
  $imports=$imports.Replace(
    'from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile',
    'from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile'
  )
}
if($imports -notmatch 'energy_intelligence import refresh_energy_intelligence'){
  $imports=$imports.Replace(
    'from ..importer import import_invoices',
    'from ..importer import import_invoices'+"`r`n"+'from ..energy_intelligence import refresh_energy_intelligence'
  )
}
$old='async def upload_invoices(organization_id: str=Form(...), file: UploadFile=File(...), user:CurrentUser=Depends(current_user)):'
$new='async def upload_invoices(background_tasks: BackgroundTasks, organization_id: str=Form(...), file: UploadFile=File(...), user:CurrentUser=Depends(current_user)):'
if($imports.Contains($old)){$imports=$imports.Replace($old,$new)}
$oldReturn='    return import_invoices(organization_id,user.id,file.filename or "facturas.zip",payload)'
$newReturn=@'
    result=import_invoices(organization_id,user.id,file.filename or "facturas.zip",payload)
    background_tasks.add_task(refresh_energy_intelligence, organization_id)
    return result
'@
if($imports.Contains($oldReturn) -and $imports -notmatch 'background_tasks\.add_task'){
  $imports=$imports.Replace($oldReturn,$newReturn)
}
Set-Content $importsPath $imports -Encoding UTF8

# AI: cargar conocimiento preprocesado y priorizarlo
$aiPath=Join-Path $routers "ai.py"
$ai=Get-Content $aiPath -Raw
if($ai -notmatch 'load_energy_knowledge'){
  $ai=$ai.Replace(
    'from ..db import admin_db',
    'from ..db import admin_db'+"`r`n"+'from ..energy_intelligence import load_energy_knowledge'
  )
}
if($ai -notmatch 'energy_knowledge = load_energy_knowledge'){
  $anchor='    db = admin_db()'
  $idx=$ai.IndexOf($anchor,$ai.IndexOf('def _build_context'))
  if($idx -lt 0){throw "No encontre _build_context para insertar conocimiento."}
  $insert=$anchor+"`r`n"+'    energy_knowledge = load_energy_knowledge(organization_id)'
  $ai=$ai.Remove($idx,$anchor.Length).Insert($idx,$insert)
}
if($ai -notmatch '"energy_knowledge": energy_knowledge'){
  $anchor='        "latest_period": latest,'
  if($ai.Contains($anchor)){
    $ai=$ai.Replace($anchor,$anchor+"`r`n"+'        "energy_knowledge": energy_knowledge,')
  }else{
    throw "No encontre latest_period en retorno de IA."
  }
}
if($ai -notmatch 'PRIORIZÁ energy_knowledge'){
  $prompt='Respondé en español claro y profesional. Analizá SOLO los datos que recibís en CONTEXTO.'
  if($ai.Contains($prompt)){
    $ai=$ai.Replace(
      $prompt,
      $prompt+"`r`n"+'PRIORIZÁ energy_knowledge.findings y energy_knowledge.snapshots: son la capa analítica precalculada y validada por reglas del sistema.'
    )
  }
}
Set-Content $aiPath $ai -Encoding UTF8

# Verificación
$okMain=(Get-Content $mainPath -Raw) -match 'intelligence\.router'
$okImports=(Get-Content $importsPath -Raw) -match 'background_tasks\.add_task'
$okAi=(Get-Content $aiPath -Raw) -match 'energy_knowledge'
$okService=Test-Path (Join-Path $back "energy_intelligence.py")

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host " Router inteligencia: $okMain"
Write-Host " Refresco automatico: $okImports"
Write-Host " IA usa capa analitica: $okAi"
Write-Host " Servicio analitico: $okService"

if(-not ($okMain -and $okImports -and $okAi -and $okService)){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "V47 aplicado correctamente." -ForegroundColor Green
Write-Host "IMPORTANTE: las tablas de Supabase ya fueron creadas en la base." -ForegroundColor Green
Write-Host "Despues del deploy, ejecutar una vez POST /api/organizations/{id}/energy-intelligence/refresh" -ForegroundColor Yellow
Write-Host "o cargar una nueva factura; el refresco se ejecuta automaticamente." -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Read-Host "ENTER para cerrar"
