$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$file = Join-Path $repo "front\app\public-lighting-panel.tsx"

if(-not (Test-Path $file)){
    throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $file "$file.bak-$stamp" -Force

$text = Get-Content $file -Raw -Encoding UTF8

# 1) Insertar cálculo del último período real desde el array GENERAL de invoices
$anchor = '  const [selected,setSelected]=useState<PLRow|null>(null);'
if(-not $text.Contains($anchor)){
    throw "No encontré el estado selected en public-lighting-panel.tsx."
}

$insert = @'
  const [selected,setSelected]=useState<PLRow|null>(null);

  // Fuente de verdad del período inicial:
  // usamos las facturas generales que ya carga la aplicación.
  // Así AP no depende del período por defecto que devuelva un backend viejo/cacheado.
  const latestGeneralPeriod=useMemo(()=>{
    const periods=invoices
      .map(i=>String(i.billing_period||i.period_start||"").slice(0,7))
      .filter(Boolean)
      .sort((a,b)=>b.localeCompare(a));
    return periods[0]||"";
  },[invoices]);

  useEffect(()=>{
    if(!period&&latestGeneralPeriod){
      setPeriod(latestGeneralPeriod);
    }
  },[period,latestGeneralPeriod]);
'@

$text = $text.Replace($anchor,$insert)

# 2) Reemplazar el useEffect de carga AP.
#    Ya NO hacemos una primera consulta sin período:
#    esperamos a conocer latestGeneralPeriod y consultamos directamente ese mes.
$pattern = 'useEffect\(\(\)=>\{\s*if\(!organizationId\)return;[\s\S]*?\},\[session,organizationId,period\]\);'
$replacement = @'
useEffect(()=>{
    if(!organizationId||!period)return;

    let cancelled=false;
    setLoading(true);
    setError("");

    getAnalysis(session,organizationId,period)
      .then(result=>{
        if(cancelled)return;
        setData(result);
      })
      .catch(e=>!cancelled&&setError(e instanceof Error?e.message:"No se pudo cargar Alumbrado Público"))
      .finally(()=>!cancelled&&setLoading(false));

    return()=>{cancelled=true};
  },[session,organizationId,period]);
'@

$rx = [regex]::new($pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
if(-not $rx.IsMatch($text)){
    throw "No encontré el useEffect actual de Alumbrado Público."
}
$text = $rx.Replace($text,$replacement,1)

Set-Content $file -Value $text -Encoding UTF8

Write-Host ""
Write-Host "AP FORZAR ULTIMO PERIODO V8 aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Ahora AP toma el período inicial directamente del array GENERAL invoices." -ForegroundColor Cyan
Write-Host "No depende del período por defecto del endpoint remoto."
Write-Host ""
Write-Host "Backup: $file.bak-$stamp"
