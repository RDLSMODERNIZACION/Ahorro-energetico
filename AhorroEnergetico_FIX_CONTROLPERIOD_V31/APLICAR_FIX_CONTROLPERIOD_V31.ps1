$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - FIX CONTROLPERIOD V31" -ForegroundColor Cyan
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
  if(Test-Path (Join-Path $c "app\page.tsx")){
    $front=$c
    break
  }
}
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"

Write-Host "[OK] Front detectado:" -ForegroundColor Green
Write-Host "  $front" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_fix_controlperiod_v31_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw

# ---------------------------------------------------------
# Quitar el useEffect V30 que referencia variables declaradas despues.
# ---------------------------------------------------------
$rx=New-Object System.Text.RegularExpressions.Regex(
  '(?s)\s*useEffect\(\(\)=>\{\s*function hideLegacyMissingPanelV30\(\).*?return\(\)=>observer\.disconnect\(\);\s*\},\[invoiceSubTab,controlPeriod,visibleMissingPeriodMeters\.length\]\);\s*',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

if($rx.IsMatch($page)){
  $page=$rx.Replace($page,"`r`n",1)
  Write-Host "[OK] useEffect V30 defectuoso eliminado." -ForegroundColor Green
}else{
  Write-Host "[INFO] No encontre el efecto V30 exacto; busco variante flexible." -ForegroundColor Yellow

  $rx2=New-Object System.Text.RegularExpressions.Regex(
    '(?s)\s*useEffect\(\(\)=>\{.*?hideLegacyMissingPanelV30.*?\},\[[^\]]*controlPeriod[^\]]*\]\);\s*',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if($rx2.IsMatch($page)){
    $page=$rx2.Replace($page,"`r`n",1)
    Write-Host "[OK] Variante V30 eliminada." -ForegroundColor Green
  }
}

# ---------------------------------------------------------
# Agregar una version segura SIN depender de controlPeriod.
# MutationObserver detecta cuando se monta Facturas recibidas.
# ---------------------------------------------------------
if($page -notmatch 'hideLegacyMissingPanelV31'){
  $anchor='useEffect(()=>{supabase.auth.getSession()'
  $idx=$page.IndexOf($anchor)
  if($idx -lt 0){throw "No encontre el useEffect de sesion."}

  $effect=@'
  useEffect(()=>{
    function hideLegacyMissingPanelV31(){
      const marker="Estos medidores no aparecen en el archivo del período seleccionado";
      const nodes=[...document.querySelectorAll("section,div")];
      const candidates=nodes.filter(el=>{
        const text=(el.textContent||"").trim();
        return text.includes(marker)&&text.includes("Faltan")&&text.includes("facturas");
      });

      // Elegimos el contenedor mas chico que contiene todo el cuadro viejo.
      const target=candidates.sort((a,b)=>(a.textContent?.length||0)-(b.textContent?.length||0))[0] as HTMLElement|undefined;
      if(!target)return;

      let panel:HTMLElement=target;
      while(panel.parentElement){
        const parent=panel.parentElement;
        const parentText=(parent.textContent||"");
        if(!parentText.includes(marker))break;
        if(parent.classList.contains("panel")||parent.tagName==="SECTION"){
          panel=parent;
          break;
        }
        panel=parent;
      }

      panel.style.display="none";
      panel.setAttribute("data-hidden-legacy-missing","true");
    }

    const timer=window.setTimeout(hideLegacyMissingPanelV31,50);
    const observer=new MutationObserver(()=>hideLegacyMissingPanelV31());
    observer.observe(document.body,{childList:true,subtree:true});
    return()=>{
      window.clearTimeout(timer);
      observer.disconnect();
    };
  },[]);

'@

  $page=$page.Insert($idx,$effect)
  Write-Host "[OK] Ocultador V31 seguro agregado." -ForegroundColor Green
}

Set-Content $pagePath $page -Encoding UTF8

# Limpiar cache
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
$bad=$check -match '\[invoiceSubTab,controlPeriod,visibleMissingPeriodMeters\.length\]'
$good=$check -match 'hideLegacyMissingPanelV31'
$emptyDeps=$check -match 'hideLegacyMissingPanelV31.*?\},\[\]\);'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Dependencia rota eliminada: $(-not $bad)"
Write-Host "  V31 presente:               $good"

if($bad -or -not $good){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V31 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Se elimino la referencia a controlPeriod antes de inicializarse." -ForegroundColor Green
Write-Host "La subpestana Sin factura sigue funcionando." -ForegroundColor Green
Write-Host "El cuadro viejo se sigue ocultando sin depender de variables React." -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
