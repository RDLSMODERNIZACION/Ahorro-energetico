$ErrorActionPreference="Stop"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " AHORRO ENERGETICO - IA RESPUESTAS CLICK V40" -ForegroundColor Cyan
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
if(-not $front){throw "No encontre front\app\page.tsx."}

$pagePath=Join-Path $front "app\page.tsx"
$cssPath=Join-Path $front "app\globals.css"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $front "backup_ia_respuestas_click_v40_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $pagePath (Join-Path $backup "page.tsx") -Force
Copy-Item $cssPath (Join-Path $backup "globals.css") -Force

$page=Get-Content $pagePath -Raw

# 1) Reemplazar helper renderAiRichText para volver clickeables referencias a medidores/suministros.
$start=$page.IndexOf("function renderAiRichText(text:string){")
$end=$page.IndexOf("export default function Home(){")
if($start -lt 0 -or $end -lt 0 -or $end -le $start){throw "No encontre renderAiRichText."}

$newHelper=@'
function renderAiRichText(text:string,onOpenReference?:(reference:string)=>void){
  const normalized=text
    .replace(/\r/g,"")
    .replace(/\s+(?=\d+\.\s+\*\*)/g,"\n")
    .replace(/\s+(?=•\s+)/g,"\n")
    .replace(/\s+(?=-\s+\*\*)/g,"\n")
    .trim();

  const openRef=(value:string)=>{
    const cleaned=value
      .replace(/\*\*/g,"")
      .replace(/^(medidor|suministro|id)\s*[:#-]?\s*/i,"")
      .trim();
    if(cleaned)onOpenReference?.(cleaned);
  };

  const isReference=(value:string)=>{
    const v=value.replace(/\*\*/g,"").trim();
    return /(?:medidor|suministro|id)\s*[:#-]?\s*[A-Za-z0-9-]{3,}/i.test(v)
      || /^[0-9]{5,12}$/.test(v);
  };

  const renderInline=(line:string,keyPrefix:string)=>{
    const parts=line.split(/(\*\*[^*]+\*\*)/g).filter(Boolean);
    return parts.map((part,index)=>{
      if(part.startsWith("**")&&part.endsWith("**")){
        const label=part.slice(2,-2);
        if(onOpenReference&&isReference(label)){
          return <button type="button" className="ai-inline-link" key={`${keyPrefix}-b-${index}`} onClick={()=>openRef(label)}>{label}</button>;
        }
        return <strong key={`${keyPrefix}-b-${index}`}>{label}</strong>;
      }
      return <span key={`${keyPrefix}-t-${index}`}>{part}</span>;
    });
  };

  const clickFromLine=(line:string)=>{
    if(!onOpenReference)return;
    const meter=line.match(/medidor\s*[:#-]?\s*([A-Za-z0-9-]{3,})/i);
    if(meter){openRef(meter[1]);return}
    const supply=line.match(/suministro\s*[:#-]?\s*([A-Za-z0-9-]{3,})/i);
    if(supply){openRef(supply[1]);}
  };

  return normalized.split("\n").filter(Boolean).map((raw,index)=>{
    const line=raw.trim();
    const numbered=line.match(/^(\d+)\.\s+(.*)$/);
    const bullet=line.match(/^(?:•|-)\s+(.*)$/);
    const clickable=Boolean(onOpenReference)&&/(medidor|suministro)\s*[:#-]?\s*[A-Za-z0-9-]{3,}/i.test(line);

    if(numbered){
      return <div className={`ai-rich-item${clickable?" clickable":""}`} key={`n-${index}`} onClick={()=>clickable&&clickFromLine(numbered[2])}>
        <span className="ai-rich-number">{numbered[1]}</span>
        <div>{renderInline(numbered[2],`n-${index}`)}</div>
        {clickable&&<em className="ai-open-hint">Abrir análisis →</em>}
      </div>;
    }
    if(bullet){
      return <div className={`ai-rich-item${clickable?" clickable":""}`} key={`u-${index}`} onClick={()=>clickable&&clickFromLine(bullet[1])}>
        <span className="ai-rich-bullet">•</span>
        <div>{renderInline(bullet[1],`u-${index}`)}</div>
        {clickable&&<em className="ai-open-hint">Abrir análisis →</em>}
      </div>;
    }
    if(line.startsWith("## ")){
      return <h4 className="ai-rich-heading" key={`h-${index}`}>{line.slice(3)}</h4>;
    }
    return <p className={`ai-rich-paragraph${clickable?" clickable":""}`} key={`p-${index}`} onClick={()=>clickable&&clickFromLine(line)}>{renderInline(line,`p-${index}`)}{clickable&&<em className="ai-open-hint">Abrir análisis →</em>}</p>;
  });
}
'@

$page=$page.Substring(0,$start)+$newHelper+"`r`n"+$page.Substring($end)

# 2) Agregar función en Home para resolver medidor/suministro/id y abrir análisis individual.
$anchor='async function updateMeterStatus'
$idx=$page.IndexOf($anchor)
if($idx -lt 0){throw "No encontre anchor updateMeterStatus."}

$fn=@'
function openAiReference(reference:string){
  const ref=reference.trim().toLowerCase().replace(/\s+/g,"");
  const normalize=(v?:string)=>String(v||"").toLowerCase().replace(/\s+/g,"").replace(/^0+/,"");

  const meter=meters.find(m=>
    normalize(m.meter_number)===normalize(ref) ||
    normalize(m.supply_number)===normalize(ref) ||
    normalize(m.tracking_code)===normalize(ref) ||
    normalize(m.id)===normalize(ref)
  );

  if(!meter){
    setToast(`No encontré el medidor/suministro ${reference}`);
    setTimeout(()=>setToast(""),3500);
    return;
  }

  const latest=[...invoices]
    .filter(i=>i.meter_id===meter.id)
    .sort((a,b)=>invoiceMonth(b).localeCompare(invoiceMonth(a)))[0];

  if(latest){
    setTab("invoices");
    setInvoiceSubTab("received");
    setSelectedMeter(meter.id);
    setSelectedInvoice(latest);
    const p=invoiceMonth(latest);
    if(p){
      setYearFilter(p.slice(0,4));
      setMonthFilter(p.slice(5,7));
    }
  }else{
    setToast(`El medidor ${meter.meter_number||reference} no tiene factura para abrir`);
    setTimeout(()=>setToast(""),3500);
  }
}

'@
$page=$page.Insert($idx,$fn)

# 3) Pasar callback al render de respuesta IA.
$old='renderAiRichText(aiAnswer)'
$new='renderAiRichText(aiAnswer,openAiReference)'
if($page.Contains($old)){
  $page=$page.Replace($old,$new)
}elseif($page -notmatch 'renderAiRichText\(aiAnswer,openAiReference\)'){
  throw "No encontre renderAiRichText(aiAnswer)."
}

Set-Content $pagePath $page -Encoding UTF8

# 4) CSS
$css=Get-Content $cssPath -Raw
$css=[regex]::Replace($css,'(?s)/\* === IA RESPUESTAS CLICK V40 START === \*/.*?/\* === IA RESPUESTAS CLICK V40 END === \*/','')
$block=@'

/* === IA RESPUESTAS CLICK V40 START === */
.ai-rich-item.clickable,
.ai-rich-paragraph.clickable{
  cursor:pointer;
  transition:background .15s ease, transform .15s ease;
}
.ai-rich-item.clickable:hover,
.ai-rich-paragraph.clickable:hover{
  background:#f1f8f4;
}
.ai-rich-item.clickable{
  border-radius:12px;
  padding:10px 12px;
  margin-left:-12px;
  margin-right:-12px;
}
.ai-inline-link{
  appearance:none;
  border:0;
  background:transparent;
  padding:0;
  margin:0;
  font:inherit;
  font-weight:800;
  color:#0b7a52;
  text-decoration:underline;
  text-underline-offset:3px;
  cursor:pointer;
}
.ai-open-hint{
  margin-left:auto;
  padding-left:12px;
  font-size:11px;
  font-style:normal;
  font-weight:750;
  color:#0b7a52;
  white-space:nowrap;
}
/* === IA RESPUESTAS CLICK V40 END === */
'@
$css=$css.TrimEnd()+"`r`n"+$block+"`r`n"
Set-Content $cssPath $css -Encoding UTF8

# cache
foreach($p in @((Join-Path $front ".next"),(Join-Path $front "node_modules\.vite"),(Join-Path $front ".vite"))){
  if(Test-Path $p){Remove-Item $p -Recurse -Force}
}

$check=Get-Content $pagePath -Raw
if($check -notmatch 'openAiReference' -or $check -notmatch 'renderAiRichText\(aiAnswer,openAiReference\)'){
  throw "La verificacion final fallo."
}

Write-Host ""
Write-Host "V40 aplicado correctamente." -ForegroundColor Green
Write-Host "Las respuestas IA que nombren Medidor o Suministro ahora pueden abrir el análisis individual." -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Read-Host "ENTER para cerrar"
