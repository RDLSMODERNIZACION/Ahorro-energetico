$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - UBICACION AL FONDO V36" -ForegroundColor Cyan
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
if(-not $front){ throw "No encontre front\app\page.tsx." }

$pagePath=Join-Path $front "app\page.tsx"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ubicacion_fondo_v36_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

# Evitar duplicados
if($page -match 'moveMeterLocationPanelV36'){
  Write-Host "[OK] V36 ya estaba aplicado." -ForegroundColor DarkGreen
}else{
  $anchor='  useEffect(()=>{supabase.auth.getSession().then(({data})=>{setSession(data.session);setAuthReady(true)});const{data}=supabase.auth.onAuthStateChange((_e,s)=>setSession(s));return()=>data.subscription.unsubscribe()},[]);'
  $idx=$page.IndexOf($anchor)
  if($idx -lt 0){
    throw "No encontre el useEffect base para insertar V36."
  }
  $insertAt=$idx + $anchor.Length

  $effect=@'

  useEffect(()=>{
    if(!selectedInvoice) return;

    function moveMeterLocationPanelV36(){
      const nodes=[...document.querySelectorAll("section,div")];
      const locationPanel=nodes.find((el:any)=>{
        const text=(el.textContent||"").trim();
        return text.includes("Ubicación del medidor") && text.includes("Latitud") && text.includes("Longitud");
      }) as HTMLElement|undefined;

      if(!locationPanel) return;
      const parent=locationPanel.parentElement as HTMLElement|null;
      if(!parent) return;

      if(parent.lastElementChild!==locationPanel){
        parent.appendChild(locationPanel);
      }
    }

    const timer=window.setTimeout(moveMeterLocationPanelV36,80);
    const observer=new MutationObserver(()=>moveMeterLocationPanelV36());
    observer.observe(document.body,{childList:true,subtree:true});

    return ()=>{
      window.clearTimeout(timer);
      observer.disconnect();
    };
  },[selectedInvoice?.id]);
'@

  $page=$page.Insert($insertAt,$effect)
  Write-Host "[OK] Efecto V36 agregado a page.tsx." -ForegroundColor Green
}

Set-Content $pagePath $page -Encoding UTF8

# Limpiar cache
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){ Remove-Item $p -Recurse -Force }
}

$check=Get-Content $pagePath -Raw
$ok = $check -match 'moveMeterLocationPanelV36' -and $check -match 'selectedInvoice\?\.id'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  V36 presente: $ok"

if(-not $ok){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V36 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ahora, al abrir una factura:" -ForegroundColor White
Write-Host " - la seccion 'Ubicación del medidor' se mueve al final" -ForegroundColor Green
Write-Host " - queda debajo del resto del detalle" -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
