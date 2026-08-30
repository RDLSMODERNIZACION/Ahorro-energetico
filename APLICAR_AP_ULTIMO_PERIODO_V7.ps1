$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$file = Join-Path $repo "front\app\public-lighting-panel.tsx"

if(-not (Test-Path $file)){
    throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $file "$file.bak-$stamp" -Force

$text = Get-Content $file -Raw -Encoding UTF8

# 1) Reemplazar el estado de período para que arranque explícitamente sin valor.
# Ya suele estar así, pero se deja normalizado.
$text = [regex]::Replace(
  $text,
  'const\s+\[period,setPeriod\]\s*=\s*useState\("[^"]*"\);',
  'const [period,setPeriod]=useState("");',
  1
)

# 2) Reemplazar el useEffect de carga de AP por uno que:
#    - primera carga SIEMPRE pide sin billing_period
#    - toma el período más nuevo devuelto por backend
#    - solo después permite navegar manualmente por períodos viejos
$pattern = 'useEffect\(\(\)=>\{\s*if\(!organizationId\)return;[\s\S]*?\},\[session,organizationId,period\]\);'

$replacement = @'
useEffect(()=>{
    if(!organizationId)return;

    let cancelled=false;
    setLoading(true);
    setError("");

    // Si period está vacío, el backend debe resolver el último período disponible.
    // Una vez cargado, adoptamos SIEMPRE data.periods[0] (orden descendente)
    // como período inicial real.
    getAnalysis(session,organizationId,period||undefined)
      .then(result=>{
        if(cancelled)return;

        const latest=(result.periods||[])[0]||result.billing_period||"";

        // Primera entrada al módulo:
        // ignoramos cualquier billing_period viejo que pudiera venir cacheado
        // y fijamos el último período real disponible.
        if(!period && latest && result.billing_period!==latest){
          setPeriod(latest);
          return;
        }

        setData(result);

        if(!period && latest){
          setPeriod(latest);
        }
      })
      .catch(e=>!cancelled&&setError(e instanceof Error?e.message:"No se pudo cargar Alumbrado Público"))
      .finally(()=>!cancelled&&setLoading(false));

    return()=>{cancelled=true};
  },[session,organizationId,period]);
'@

$rx = [regex]::new($pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
if(-not $rx.IsMatch($text)){
    throw "No encontré el useEffect de carga de Alumbrado Público."
}
$text = $rx.Replace($text,$replacement,1)

Set-Content $file -Value $text -Encoding UTF8

Write-Host ""
Write-Host "AP ULTIMO PERIODO V7 aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Al entrar a Alumbrado Público ahora toma siempre el período más nuevo disponible." -ForegroundColor Cyan
Write-Host "Después podés cambiar manualmente a períodos anteriores desde el selector."
Write-Host ""
Write-Host "Backup creado: $file.bak-$stamp"
