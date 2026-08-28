$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - UBICACION DE MEDIDOR V9" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here))|Select-Object -Unique

$root=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "front\app\invoice-analysis-panel.tsx")) -and
     (Test-Path (Join-Path $c "back\app\routers\catalog.py"))){
    $root=$c;break
  }
}
if(-not $root){
  if((Split-Path $here -Leaf) -eq "front"){
    $candidate=Split-Path -Parent $here
    if(Test-Path (Join-Path $candidate "back\app\routers\catalog.py")){$root=$candidate}
  }
}
if(-not $root){throw "No encontre la raiz Ahorro-energetico con front y back."}

$front=Join-Path $root "front"
$back=Join-Path $root "back"
$analysisPath=Join-Path $front "app\invoice-analysis-panel.tsx"
$cssPath=Join-Path $front "app\globals.css"
$editorTarget=Join-Path $front "app\meter-location-editor.tsx"
$catalogPath=Join-Path $back "app\routers\catalog.py"

Write-Host "[OK] Proyecto:" -ForegroundColor Green
Write-Host "  $root" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_ubicacion_medidor_v9_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $analysisPath (Join-Path $backup "invoice-analysis-panel.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force
Copy-Item $catalogPath (Join-Path $backup "catalog.py") -Force
if(Test-Path $editorTarget){Copy-Item $editorTarget (Join-Path $backup "meter-location-editor.tsx") -Force}

# -------------------------------------------
# FRONT: componente de mapa
# -------------------------------------------
Copy-Item (Join-Path $scriptDir "meter-location-editor.tsx") $editorTarget -Force
Write-Host "[OK] Editor de mapa instalado." -ForegroundColor Green

$analysis=Get-Content $analysisPath -Raw

if($analysis -notmatch 'MeterLocationEditor'){
  $anchor='import { useMemo, useState } from "react";'
  if($analysis.Contains($anchor)){
    $analysis=$analysis.Replace($anchor,$anchor+"`r`n"+'import { MeterLocationEditor } from "./meter-location-editor";')
  } else {
    throw "No encontre el import de React en invoice-analysis-panel.tsx."
  }
}

if($analysis -notmatch '<MeterLocationEditor'){
  # Se inserta antes de Conceptos facturados.
  $anchor='<section className="invoice-analysis-panel">'+"`r`n"+'        <h3>Conceptos facturados</h3>'
  if($analysis.Contains($anchor)){
    $insert='<MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>'+"`r`n`r`n      "+$anchor
    $analysis=$analysis.Replace($anchor,$insert)
  }else{
    # Variante tolerante a espacios.
    $pattern='(?s)(<section className="invoice-analysis-panel">\s*<h3>Conceptos facturados</h3>)'
    if([regex]::IsMatch($analysis,$pattern)){
      $analysis=[regex]::Replace($analysis,$pattern,'<MeterLocationEditor meterId={selected.meter_id} label={`${m?.service_name||m?.sites?.name||"Servicio"} · Medidor ${m?.meter_number||"S/D"}`}/>'+"`r`n`r`n      "+'$1',1)
    }else{throw "No encontre la seccion Conceptos facturados para insertar el mapa."}
  }
  Write-Host "[OK] Ubicacion agregada al analisis individual." -ForegroundColor Green
}else{
  Write-Host "[OK] Ubicacion ya estaba agregada al analisis." -ForegroundColor DarkGreen
}
Set-Content $analysisPath $analysis -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === UBICACION MEDIDOR V9 START === \*/.*?/\* === UBICACION MEDIDOR V9 END === \*/','')
$cssBlock=Get-Content (Join-Path $scriptDir "ubicacion-medidor-v9.css") -Raw
$css=$css.TrimEnd()+"`r`n"+$cssBlock+"`r`n"
Set-Content $cssPath $css -Encoding UTF8
Write-Host "[OK] Estilos del mapa agregados." -ForegroundColor Green

# -------------------------------------------
# BACK: GET ubicacion actual.
# PUT ya existe en catalog.py; se mejora source.
# -------------------------------------------
$catalog=Get-Content $catalogPath -Raw

if($catalog -notmatch '@router\.get\("/meters/\{meter_id\}/location"\)'){
$getter=@'

@router.get("/meters/{meter_id}/location")
def get_location(meter_id: str, user: CurrentUser = Depends(current_user)):
    db = admin_db()
    meter = db.table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not meter:
        raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,meter[0]["organization_id"])
    rows = (
        db.table("meter_locations")
        .select("*")
        .eq("meter_id",meter_id)
        .is_("valid_to","null")
        .order("valid_from", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not rows:
        return None
    return rows[0]

'@
  $putAnchor='@router.put("/meters/{meter_id}/location")'
  if($catalog.Contains($putAnchor)){
    $catalog=$catalog.Replace($putAnchor,$getter+$putAnchor)
    Write-Host "[OK] Endpoint GET de ubicacion agregado al backend." -ForegroundColor Green
  }else{throw "No encontre el endpoint PUT de ubicacion existente."}
}else{
  Write-Host "[OK] Endpoint GET ya existe." -ForegroundColor DarkGreen
}

# Agrega source al registro nuevo sin cambiar el modelo.
$old='row={"meter_id":meter_id,"latitude":str(body.latitude),"longitude":str(body.longitude),"created_by":user.id}'
$new='row={"meter_id":meter_id,"latitude":str(body.latitude),"longitude":str(body.longitude),"source":"manual_map","created_by":user.id}'
if($catalog.Contains($old)){
  $catalog=$catalog.Replace($old,$new)
  Write-Host "[OK] Fuente manual_map agregada al guardado." -ForegroundColor Green
}

Set-Content $catalogPath $catalog -Encoding UTF8

# Limpia caches front.
foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificacion.
$a=Get-Content $analysisPath -Raw
$c=Get-Content $catalogPath -Raw
if(($a -match 'MeterLocationEditor') -and ($c -match '@router\.get\("/meters/\{meter_id\}/location"\)')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " UBICACION DE MEDIDOR V9 APLICADA" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora el analisis individual permite:" -ForegroundColor White
  Write-Host " - Escribir latitud y longitud" -ForegroundColor Green
  Write-Host " - Hacer clic en OpenStreetMap" -ForegroundColor Green
  Write-Host " - Arrastrar el marcador" -ForegroundColor Green
  Write-Host " - Usar la ubicacion GPS del navegador" -ForegroundColor Green
  Write-Host " - Guardar en meter_locations de Supabase" -ForegroundColor Green
  Write-Host " - Mantener historial de ubicaciones" -ForegroundColor Green
  Write-Host ""
  Write-Host "IMPORTANTE: este cambio toca FRONT y BACK." -ForegroundColor Yellow
  Write-Host "Para local:" -ForegroundColor Cyan
  Write-Host "  Terminal 1: cd `"$back`"; uvicorn app.main:app --reload" -ForegroundColor White
  Write-Host "  Terminal 2: cd `"$front`"; npm run dev" -ForegroundColor White
  Write-Host ""
  Write-Host "Si usas Render para el backend, subi/pushea tambien los cambios de back." -ForegroundColor Yellow
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
}else{throw "La verificacion final fallo."}

Read-Host "ENTER para cerrar"
