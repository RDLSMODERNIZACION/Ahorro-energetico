$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - CONECTAR IA OPENAI V12" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$here=(Get-Location).Path
$candidates=@($here,(Split-Path -Parent $here))|Select-Object -Unique
$root=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "front\app\page.tsx")) -and
     (Test-Path (Join-Path $c "back\app\main.py"))){
    $root=$c;break
  }
}
if(-not $root){throw "No encontre la raiz Ahorro-energetico con front y back."}

$front=Join-Path $root "front"
$back=Join-Path $root "back"
$pagePath=Join-Path $front "app\page.tsx"
$mainPath=Join-Path $back "app\main.py"
$requirementsPath=Join-Path $back "requirements.txt"
$aiTarget=Join-Path $back "app\routers\ai.py"

Write-Host "[OK] Proyecto:" -ForegroundColor Green
Write-Host "  $root" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_ia_openai_v12_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $mainPath (Join-Path $backup "main.py") -Force
Copy-Item $requirementsPath (Join-Path $backup "requirements.txt") -Force
if(Test-Path $aiTarget){Copy-Item $aiTarget (Join-Path $backup "ai.py") -Force}

# Backend router
Copy-Item (Join-Path $scriptDir "ai.py") $aiTarget -Force
Write-Host "[OK] Router IA/OpenAI instalado." -ForegroundColor Green

# main.py
$main=Get-Content $mainPath -Raw
$main=$main.Replace(
  'from .routers import analysis,catalog,imports,invoices,tariffs',
  'from .routers import analysis,catalog,imports,invoices,tariffs,ai'
)
if($main -notmatch 'include_router\(ai\.router'){
  $anchor='api.include_router(analysis.router,prefix="/api")'
  if($main.Contains($anchor)){
    $main=$main.Replace($anchor,$anchor+"`r`n"+'api.include_router(ai.router,prefix="/api")')
  }else{throw "No encontre include_router de analysis en main.py."}
}
Set-Content $mainPath $main -Encoding UTF8
Write-Host "[OK] Endpoint /api/ai/query conectado." -ForegroundColor Green

# Front: reemplaza runAiQuery local por llamada real al backend.
$page=Get-Content $pagePath -Raw

$pattern='(?s)  function runAiQuery\(text\?:string\)\{.*?\n  \}\n\n(?=async function updateMeterStatus)'
if([regex]::IsMatch($page,$pattern)){
$replacement=@'
  async function runAiQuery(text?:string){
    const question=(text??aiQuery).trim();
    if(!question){setAiAnswer("Escribí una consulta.");return}
    if(!session||!orgId){setAiAnswer("No hay sesión u organización activa.");return}
    setAiBusy(true);
    try{
      const result=await api<{answer:string;model?:string;latest_period?:string}>(
        "/api/ai/query",
        session,
        {method:"POST",body:JSON.stringify({organization_id:orgId,question})}
      );
      setAiAnswer(result.answer);
    }catch(error){
      setAiAnswer(error instanceof Error?error.message:"No se pudo consultar la IA");
    }finally{
      setAiBusy(false);
    }
  }

'@
  $page=[regex]::Replace($page,$pattern,$replacement,1)
  Write-Host "[OK] Front IA conectado al backend real." -ForegroundColor Green
}elseif($page -match '"/api/ai/query"'){
  Write-Host "[OK] Front ya estaba conectado a /api/ai/query." -ForegroundColor DarkGreen
}else{
  throw "No encontre la funcion runAiQuery del V11. Aplica primero V11 FIX."
}

# Cambia subtitulo para dejar claro que ya usa OpenAI.
$page=$page.Replace(
  'Primera versión: consultas inteligentes sobre los datos ya cargados.',
  'Conectado a OpenAI y a los datos energéticos de Supabase.'
)
Set-Content $pagePath $page -Encoding UTF8

# .env.example
$envExample=Join-Path $back ".env.example"
if(Test-Path $envExample){
  $env=Get-Content $envExample -Raw
  if($env -notmatch 'OPENAI_API_KEY'){
    $env=$env.TrimEnd()+"`r`nOPENAI_API_KEY=`r`nOPENAI_MODEL=gpt-5.4`r`n"
    Set-Content $envExample $env -Encoding UTF8
  }
}

# Limpia caches front
foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

# Verificacion
$m=Get-Content $mainPath -Raw
$p=Get-Content $pagePath -Raw
if(($m -match 'include_router\(ai\.router') -and ($p -match '"/api/ai/query"') -and (Test-Path $aiTarget)){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " OPENAI V12 CONECTADO EN EL CODIGO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "FALTA SOLO CONFIGURAR LA CLAVE EN EL BACKEND." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "NO pegues la API key dentro del front ni de page.tsx." -ForegroundColor Red
  Write-Host "Guardala como variable de entorno OPENAI_API_KEY." -ForegroundColor White
  Write-Host ""
  Write-Host "Para probar LOCAL en esta sesion de PowerShell:" -ForegroundColor Cyan
  Write-Host '  $env:OPENAI_API_KEY="TU_CLAVE_OPENAI"' -ForegroundColor White
  Write-Host '  $env:OPENAI_MODEL="gpt-5.4"' -ForegroundColor White
  Write-Host "  cd `"$back`"" -ForegroundColor White
  Write-Host "  uvicorn app.main:app --reload" -ForegroundColor White
  Write-Host ""
  Write-Host "Para PRODUCCION EN RENDER:" -ForegroundColor Cyan
  Write-Host "  Environment -> Add Environment Variable" -ForegroundColor White
  Write-Host "  OPENAI_API_KEY = tu clave" -ForegroundColor White
  Write-Host "  OPENAI_MODEL = gpt-5.4" -ForegroundColor White
  Write-Host "  Luego redeploy del backend." -ForegroundColor White
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
