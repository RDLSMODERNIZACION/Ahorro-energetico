$ErrorActionPreference="Stop"

$here=(Get-Location).Path
$root=$null
foreach($c in @($here,(Split-Path -Parent $here))){
  if((Test-Path (Join-Path $c "front\app\invoice-analysis-panel.tsx")) -and
     (Test-Path (Join-Path $c "back\app\routers\catalog.py"))){$root=$c;break}
}
if(-not $root){throw "No encontre front y back del proyecto."}

$panelPath=Join-Path $root "front\app\invoice-analysis-panel.tsx"
$cssPath=Join-Path $root "front\app\globals.css"
$catalogPath=Join-Path $root "back\app\routers\catalog.py"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_editar_nombre_v41_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $panelPath (Join-Path $backup "invoice-analysis-panel.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force
Copy-Item $catalogPath (Join-Path $backup "catalog.py") -Force

# BACKEND
$catalog=Get-Content $catalogPath -Raw
if($catalog -notmatch 'class MeterNameUpdate'){
  $catalog=$catalog.Replace('class BillingStatusUpdate(BaseModel):',"class MeterNameUpdate(BaseModel):`r`n    service_name: str`r`n`r`nclass BillingStatusUpdate(BaseModel):")
}
if($catalog -notmatch '/meters/\{meter_id\}/name'){
$endpoint=@'
@router.put("/meters/{meter_id}/name")
def update_meter_name(meter_id: str, body: MeterNameUpdate, user: CurrentUser = Depends(current_user)):
    db = admin_db()
    rows = db.table("meters").select("organization_id").eq("id",meter_id).limit(1).execute().data
    if not rows:
        raise HTTPException(404,"Medidor inexistente")
    require_org(user.id,rows[0]["organization_id"],write=True)
    name = body.service_name.strip()
    if len(name) < 2:
        raise HTTPException(422,"El nombre debe tener al menos 2 caracteres")
    updated = db.table("meters").update({"service_name":name,"updated_at":datetime.now(timezone.utc).isoformat()}).eq("id",meter_id).execute().data
    return updated[0]

'@
  $catalog=$catalog.Replace('@router.put("/meters/{meter_id}/billing-status")',$endpoint+'@router.put("/meters/{meter_id}/billing-status")')
}
Set-Content $catalogPath $catalog -Encoding UTF8

# FRONT
$panel=Get-Content $panelPath -Raw
if($panel -notmatch 'from "\./lib/supabase"'){
  $panel=$panel.Replace('import { MeterLocationEditor } from "./meter-location-editor";','import { MeterLocationEditor } from "./meter-location-editor";'+"`r`n"+'import { supabase } from "./lib/supabase";')
}
if($panel -notmatch 'const API="https://ahorro-energetico.onrender.com";'){
  $panel=$panel.Replace('const money=new Intl.NumberFormat','const API="https://ahorro-energetico.onrender.com";'+"`r`n"+'const money=new Intl.NumberFormat')
}
if($panel -notmatch 'editingName'){
  $panel=$panel.Replace(
    'const[metric,setMetric]=useState<Metric>("kwh");',
    'const[metric,setMetric]=useState<Metric>("kwh");'+
    "`r`n  "+'const[editingName,setEditingName]=useState(false);'+
    "`r`n  "+'const[nameDraft,setNameDraft]=useState(invoice.meters?.service_name||invoice.meters?.sites?.name||"");'+
    "`r`n  "+'const[displayName,setDisplayName]=useState(invoice.meters?.service_name||invoice.meters?.sites?.name||"Servicio sin nombre");'+
    "`r`n  "+'const[nameBusy,setNameBusy]=useState(false);'+
    "`r`n  "+'const[nameError,setNameError]=useState("");'
  )
}

if($panel -notmatch 'async function saveMeterName'){
$fn=@'
  async function saveMeterName(){
    const clean=nameDraft.trim();
    if(clean.length<2){setNameError("Ingresá un nombre válido.");return}
    setNameBusy(true);setNameError("");
    try{
      const{data}=await supabase.auth.getSession();
      if(!data.session)throw new Error("Sesión vencida");
      const response=await fetch(`${API}/api/meters/${selected.meter_id}/name`,{
        method:"PUT",
        headers:{Authorization:`Bearer ${data.session.access_token}`,"Content-Type":"application/json"},
        body:JSON.stringify({service_name:clean})
      });
      const body=await response.text();
      if(!response.ok){
        let message=body;
        try{message=JSON.parse(body).detail||body}catch{}
        throw new Error(message);
      }
      setDisplayName(clean);
      if(m)m.service_name=clean;
      setEditingName(false);
    }catch(error){
      setNameError(error instanceof Error?error.message:"No se pudo guardar el nombre");
    }finally{setNameBusy(false)}
  }

'@
  $panel=$panel.Replace('  return <div className="invoice-analysis-backdrop">',$fn+'  return <div className="invoice-analysis-backdrop">')
}

$old='<h2>{m?.service_name||m?.sites?.name||"Servicio sin nombre"}</h2>'
if($panel.Contains($old)){
$new=@'
<div className="invoice-name-row">
            {editingName?
              <div className="invoice-name-editor">
                <input value={nameDraft} onChange={e=>setNameDraft(e.target.value)} autoFocus/>
                <button className="save" onClick={saveMeterName} disabled={nameBusy}>{nameBusy?"Guardando…":"Guardar"}</button>
                <button className="cancel" onClick={()=>{setEditingName(false);setNameError("");setNameDraft(displayName)}}>Cancelar</button>
              </div>
              :<>
                <h2>{displayName}</h2>
                <button className="invoice-edit-name" onClick={()=>{setNameDraft(displayName);setEditingName(true)}}>✎ Editar nombre</button>
              </>
            }
          </div>
          {nameError&&<div className="invoice-name-error">{nameError}</div>}
'@
  $panel=$panel.Replace($old,$new)
}
Set-Content $panelPath $panel -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
if($css -notmatch 'EDITAR NOMBRE V41'){
$css += @'

/* === EDITAR NOMBRE V41 START === */
.invoice-name-row{display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.invoice-name-row h2{margin:0}
.invoice-edit-name{border:1px solid rgba(255,255,255,.22);background:rgba(255,255,255,.10);color:#fff;border-radius:9px;padding:8px 12px;font-size:12px;font-weight:750;cursor:pointer}
.invoice-edit-name:hover{background:rgba(255,255,255,.17)}
.invoice-name-editor{display:flex;gap:8px;align-items:center;width:min(760px,100%)}
.invoice-name-editor input{min-width:320px;flex:1;border:1px solid rgba(255,255,255,.30);background:#fff;color:#15241d;border-radius:9px;padding:10px 12px;font-size:17px;font-weight:650;outline:none}
.invoice-name-editor button{border:0;border-radius:9px;padding:10px 13px;font-weight:750;cursor:pointer}
.invoice-name-editor .save{background:#16935f;color:#fff}
.invoice-name-editor .cancel{background:rgba(255,255,255,.12);color:#fff;border:1px solid rgba(255,255,255,.20)}
.invoice-name-error{margin-top:7px;color:#ffd6cf;font-size:12px;font-weight:650}
/* === EDITAR NOMBRE V41 END === */
'@
}
Set-Content $cssPath $css -Encoding UTF8

if((Get-Content $panelPath -Raw) -notmatch 'invoice-edit-name'){throw "No se aplico el front"}
if((Get-Content $catalogPath -Raw) -notmatch '/meters/\{meter_id\}/name'){throw "No se aplico el backend"}

Write-Host "V41 aplicado correctamente." -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Read-Host "ENTER para cerrar"
