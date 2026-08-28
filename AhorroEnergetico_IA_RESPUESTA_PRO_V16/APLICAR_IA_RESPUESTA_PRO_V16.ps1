$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - RESPUESTA IA PRO V16" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$here=(Get-Location).Path
$candidates=@($here,(Join-Path $here "front"),(Split-Path -Parent $here),(Join-Path (Split-Path -Parent $here) "front"))|Select-Object -Unique
$root=$null
foreach($c in $candidates){
  if((Test-Path (Join-Path $c "front\app\page.tsx")) -and
     (Test-Path (Join-Path $c "back\app\routers\ai.py"))){
    $root=$c;break
  }
}
if(-not $root){
  if((Test-Path (Join-Path $here "app\page.tsx")) -and (Test-Path (Join-Path (Split-Path -Parent $here) "back\app\routers\ai.py"))){
    $root=Split-Path -Parent $here
  }
}
if(-not $root){throw "No encontre la raiz con front y back."}

$front=Join-Path $root "front"
$back=Join-Path $root "back"
$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"
$aiPath=Join-Path $back "app\routers\ai.py"

Write-Host "[OK] Proyecto:" -ForegroundColor Green
Write-Host "  $root" -ForegroundColor White

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $root "backup_ia_respuesta_pro_v16_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force
Copy-Item $aiPath (Join-Path $backup "ai.py") -Force

# =====================================================
# FRONT
# =====================================================
$page=Get-Content $pagePath -Raw

if($page -notmatch 'function renderAiRichText'){
$helper=@'

function renderAiRichText(text:string){
  const normalized=text
    .replace(/\r/g,"")
    .replace(/\s+(?=\d+\.\s+\*\*)/g,"\n")
    .replace(/\s+(?=•\s+)/g,"\n")
    .replace(/\s+(?=-\s+\*\*)/g,"\n")
    .trim();

  const renderInline=(line:string,keyPrefix:string)=>{
    const parts=line.split(/(\*\*[^*]+\*\*)/g).filter(Boolean);
    return parts.map((part,index)=>{
      if(part.startsWith("**")&&part.endsWith("**")){
        return <strong key={`${keyPrefix}-b-${index}`}>{part.slice(2,-2)}</strong>;
      }
      return <span key={`${keyPrefix}-t-${index}`}>{part}</span>;
    });
  };

  return normalized.split("\n").filter(Boolean).map((raw,index)=>{
    const line=raw.trim();
    const numbered=line.match(/^(\d+)\.\s+(.*)$/);
    const bullet=line.match(/^(?:•|-)\s+(.*)$/);

    if(numbered){
      return <div className="ai-rich-item" key={`n-${index}`}>
        <span className="ai-rich-number">{numbered[1]}</span>
        <div>{renderInline(numbered[2],`n-${index}`)}</div>
      </div>;
    }
    if(bullet){
      return <div className="ai-rich-item" key={`u-${index}`}>
        <span className="ai-rich-bullet">•</span>
        <div>{renderInline(bullet[1],`u-${index}`)}</div>
      </div>;
    }
    if(line.startsWith("## ")){
      return <h4 className="ai-rich-heading" key={`h-${index}`}>{line.slice(3)}</h4>;
    }
    return <p className="ai-rich-paragraph" key={`p-${index}`}>{renderInline(line,`p-${index}`)}</p>;
  });
}

'@
  $anchor='export default function Home(){'
  if($page.Contains($anchor)){
    $page=$page.Replace($anchor,$helper+$anchor)
    Write-Host "[OK] Render enriquecido agregado." -ForegroundColor Green
  }else{throw "No encontre Home() para insertar renderAiRichText."}
}

# Replace plain paragraph rendering.
$old='<div><b>Asistente energético</b><p>{aiBusy?"Analizando Supabase con OpenAI…":aiAnswer}</p></div>'
$new='<div className="ai-answer-content"><b>Asistente energético</b><div className="ai-rich-response">{aiBusy?<p className="ai-rich-paragraph">Analizando Supabase con OpenAI…</p>:renderAiRichText(aiAnswer)}</div></div>'
if($page.Contains($old)){
  $page=$page.Replace($old,$new)
  Write-Host "[OK] Respuesta IA visual mejorada." -ForegroundColor Green
}elseif($page -match 'ai-rich-response'){
  Write-Host "[OK] Respuesta IA enriquecida ya estaba aplicada." -ForegroundColor DarkGreen
}else{
  # flexible fallback
  $pattern='(?s)<div><b>Asistente energético</b><p>\{aiBusy\?.*?:aiAnswer\}</p></div>'
  if([regex]::IsMatch($page,$pattern)){
    $page=[regex]::Replace($page,$pattern,$new,1)
    Write-Host "[OK] Respuesta IA mejorada con deteccion flexible." -ForegroundColor Green
  }else{
    throw "No encontre el bloque visual del Asistente energético."
  }
}

Set-Content $pagePath $page -Encoding UTF8

# CSS
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === IA RESPUESTA PRO V16 START === \*/.*?/\* === IA RESPUESTA PRO V16 END === \*/','')
$block=@'

/* === IA RESPUESTA PRO V16 START === */
.ai-answer{align-items:flex-start}
.ai-answer-content{min-width:0;flex:1}
.ai-answer-content>b{display:block;font-size:10px;margin:2px 0 10px;color:#16251e}
.ai-rich-response{display:grid;gap:9px;max-width:1180px}
.ai-rich-paragraph{margin:0!important;font-size:11px!important;line-height:1.65!important;color:#42564c!important}
.ai-rich-response strong{color:#153f31;font-weight:850}
.ai-rich-item{display:grid;grid-template-columns:28px minmax(0,1fr);gap:10px;align-items:flex-start;padding:10px 12px;border:1px solid #e2ebe6;border-radius:9px;background:#fbfdfc;font-size:10px;line-height:1.55;color:#43574d}
.ai-rich-number,.ai-rich-bullet{width:25px;height:25px;border-radius:7px;display:grid;place-items:center;background:#e8f5ee;color:#17764f;font-weight:900;font-size:9px}
.ai-rich-bullet{font-size:14px}
.ai-rich-heading{margin:6px 0 0;font-size:12px;color:#173f31}
.ai-rich-response .ai-rich-item:hover{border-color:#c9ded3;background:#f7fbf9}
@media(max-width:700px){.ai-rich-item{grid-template-columns:24px minmax(0,1fr);padding:9px}.ai-rich-number,.ai-rich-bullet{width:22px;height:22px}}
/* === IA RESPUESTA PRO V16 END === */
'@
$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# =====================================================
# BACKEND prompt: force structured output.
# =====================================================
$ai=Get-Content $aiPath -Raw

if($ai -notmatch 'FORMATO DE RESPUESTA'){
  $needle='Priorizá respuestas accionables y breves'
  $idx=$ai.IndexOf($needle)
  if($idx -ge 0){
    $end=$ai.IndexOf('"""',$idx)
    if($end -gt $idx){
      $before=$ai.Substring(0,$end)
      $after=$ai.Substring($end)
      $format=@'

FORMATO DE RESPUESTA:
- Usá párrafos cortos.
- Para rankings o múltiples hallazgos, usá una lista numerada, una línea por elemento.
- En cada elemento poné primero el nombre del servicio o medidor en negrita usando **texto**.
- Luego indicá los valores principales y una recomendación breve.
- No escribas todo en un solo párrafo.
- No uses tablas Markdown salvo que el usuario las pida.
- Cerrá con una conclusión de 1 o 2 líneas cuando aporte valor.
'@
      $ai=$before+$format+$after
      Write-Host "[OK] Prompt de OpenAI actualizado para respuestas estructuradas." -ForegroundColor Green
    }
  }
}

Set-Content $aiPath $ai -Encoding UTF8

# cache
foreach($p in @((Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"),(Join-Path $front ".vinext"),(Join-Path $front "dist"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$checkPage=Get-Content $pagePath -Raw
$checkAi=Get-Content $aiPath -Raw
if(($checkPage -match 'renderAiRichText') -and ($checkPage -match 'ai-rich-response') -and ($checkAi -match 'FORMATO DE RESPUESTA')){
  Write-Host ""
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host " V16 APLICADO Y VERIFICADO" -ForegroundColor Cyan
  Write-Host "======================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Ahora la IA muestra:" -ForegroundColor White
  Write-Host " - listas numeradas visuales" -ForegroundColor Green
  Write-Host " - negritas reales" -ForegroundColor Green
  Write-Host " - cada hallazgo en una tarjeta" -ForegroundColor Green
  Write-Host " - parrafos separados" -ForegroundColor Green
  Write-Host ""
  Write-Host "IMPORTANTE:" -ForegroundColor Yellow
  Write-Host "El front se ve local al reiniciar Vite." -ForegroundColor White
  Write-Host "Para que OpenAI entregue el formato nuevo en produccion, subi tambien back/app/routers/ai.py a Render y redeploy." -ForegroundColor White
  Write-Host ""
  Write-Host "Backup: $backup" -ForegroundColor DarkGray
}else{
  throw "La verificacion final fallo."
}

Read-Host "ENTER para cerrar"
