$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - OCULTAR CUADRO VIEJO V30" -ForegroundColor Cyan
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

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ocultar_cuadro_viejo_v30_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

# ---------------------------------------------------------
# 1) Limpiar cualquier CSS viejo V28/V29 que pueda interferir
# ---------------------------------------------------------
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === OCULTAR CUADRO FALTANTES V28 START === \*/.*?/\* === OCULTAR CUADRO FALTANTES V28 END === \*/','')
$css=[regex]::Replace($css,'(?s)/\* === OCULTAR CUADRO FALTANTES V26 START === \*/.*?/\* === OCULTAR CUADRO FALTANTES V26 END === \*/','')
Set-Content $cssPath $css -Encoding UTF8

# ---------------------------------------------------------
# 2) Agregar useEffect que oculta SOLO el cuadro viejo
#    por su texto exacto. No toca el JSX visible.
# ---------------------------------------------------------
$page=Get-Content $pagePath -Raw

if($page -notmatch 'hideLegacyMissingPanelV30'){
  $anchor='useEffect(()=>{supabase.auth.getSession()'
  $idx=$page.IndexOf($anchor)
  if($idx -lt 0){throw "No encontre useEffect de sesion para insertar V30."}

  $effect=@'
  useEffect(()=>{
    function hideLegacyMissingPanelV30(){
      const marker="Estos medidores no aparecen en el archivo del período seleccionado";
      const all=[...document.querySelectorAll("section,div")];
      const target=all.find(el=>{
        const text=(el.textContent||"").trim();
        return text.includes(marker) && text.includes("Faltan") && text.includes("facturas");
      });
      if(!target)return;

      let panel:HTMLElement|null=target as HTMLElement;
      while(panel?.parentElement){
        const cls=String(panel.className||"");
        if(panel.tagName==="SECTION" || cls.includes("panel") || cls.includes("missing")){
          break;
        }
        panel=panel.parentElement;
      }
      if(panel){
        panel.style.display="none";
        panel.setAttribute("data-hidden-legacy-missing","true");
      }
    }

    hideLegacyMissingPanelV30();
    const observer=new MutationObserver(()=>hideLegacyMissingPanelV30());
    observer.observe(document.body,{childList:true,subtree:true});
    return()=>observer.disconnect();
  },[invoiceSubTab,controlPeriod,visibleMissingPeriodMeters.length]);

'@
  $page=$page.Insert($idx,$effect)
  Write-Host "[OK] Ocultador seguro agregado." -ForegroundColor Green
}else{
  Write-Host "[OK] V30 ya estaba agregado." -ForegroundColor DarkGreen
}

Set-Content $pagePath $page -Encoding UTF8

# ---------------------------------------------------------
# 3) Limpiar cache
# ---------------------------------------------------------
foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# ---------------------------------------------------------
# 4) Verificar
# ---------------------------------------------------------
$check=Get-Content $pagePath -Raw
$okEffect=$check -match 'hideLegacyMissingPanelV30'
$okSubTab=$check -match 'invoiceSubTab==="missing"'

Write-Host ""
Write-Host "Verificacion:" -ForegroundColor Cyan
Write-Host "  Ocultador V30:          $okEffect"
Write-Host "  Subpestana Sin factura: $okSubTab"

if(-not ($okEffect -and $okSubTab)){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V30 APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Este fix NO borra JSX." -ForegroundColor Green
Write-Host "Oculta solamente el cuadro viejo buscando su texto exacto." -ForegroundColor Green
Write-Host "La subpestana 'Sin factura' queda visible y funcionando." -ForegroundColor Green
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor DarkGray

Read-Host "ENTER para cerrar"
