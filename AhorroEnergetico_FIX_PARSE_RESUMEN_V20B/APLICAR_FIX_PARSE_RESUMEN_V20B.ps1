$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - FIX PARSE RESUMEN V20B" -ForegroundColor Cyan
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
$backup=Join-Path $front "backup_fix_parse_resumen_v20b_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force

$page=Get-Content $pagePath -Raw
$before=$page

# Caso exacto del error reportado.
$page=$page.Replace('</article></div></section>}</aside>','</article></div></section>')

# Variante con espacios/saltos.
$rx1=New-Object System.Text.RegularExpressions.Regex(
  '(</article>\s*</div>\s*</section>)\s*\}\s*</aside>',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)
$page=$rx1.Replace($page,'$1',1)

# Variante anclada a executive-savings.
$rx2=New-Object System.Text.RegularExpressions.Regex(
  '(<section className="panel executive-savings">.*?</section>)\s*\}\s*</aside>',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)
$page=$rx2.Replace($page,'$1',1)

Set-Content $pagePath $page -Encoding UTF8

$check=Get-Content $pagePath -Raw
$broken=$check -match 'executive-savings.*?</section>\s*\}\s*</aside>'

if($broken){
  throw "Sigue existiendo el cierre JSX roto despues de executive-savings."
}

if($page -eq $before){
  Write-Host "[INFO] El patron exacto ya no estaba; igualmente verifique que no quede el cierre roto." -ForegroundColor Yellow
}else{
  Write-Host "[OK] Cierre JSX huérfano eliminado." -ForegroundColor Green
}

foreach($p in @(
  (Join-Path $front "node_modules\.vite"),
  (Join-Path $front ".vite"),
  (Join-Path $front ".vinext"),
  (Join-Path $front "dist")
)){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " V20B APLICADO Y VERIFICADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "El error venia del cierre sobrante: } </aside>" -ForegroundColor White
Write-Host ""
Write-Host "Backup:" -ForegroundColor DarkGray
Write-Host "  $backup" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Ahora:" -ForegroundColor Cyan
Write-Host "  cd `"$front`"" -ForegroundColor White
Write-Host "  npm run dev" -ForegroundColor White

Read-Host "ENTER para cerrar"
