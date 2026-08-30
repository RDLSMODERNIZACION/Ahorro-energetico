$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path

$Repo=$null
if (Test-Path (Join-Path $Root "front\app\invoice-analysis-panel.tsx")) {
  $Repo=$Root
} else {
  $Parent=(Resolve-Path (Join-Path $Root "..")).Path
  if (Test-Path (Join-Path $Parent "front\app\invoice-analysis-panel.tsx")) {$Repo=$Parent}
}
if(-not $Repo){throw "No encontré la raíz de Ahorro-energetico."}

$front=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$css=Join-Path $Repo "front\app\globals.css"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=Join-Path $Root "backup_v11_fix2_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item $front $backup
Copy-Item $css $backup

$text=Get-Content $front -Raw

# ---------------------------------------------------------------
# 1) Tipos: agregar available/reason si todavía no existen
# ---------------------------------------------------------------
if($text -match 'type AdvancedTariffHistoryPoint=\{'){
  if($text -notmatch 'available\?:boolean;'){
    $text=[regex]::Replace(
      $text,
      '(type AdvancedTariffHistoryPoint=\{[\s\S]*?capacity_kw:number;)',
      '$1'+"`r`n"+'  available?:boolean;'+"`r`n"+'  reason?:string|null;',
      1
    )
  }
}

# ---------------------------------------------------------------
# 2) Reemplazar el bloque tariffSaving sin depender del espaciado
# ---------------------------------------------------------------
if($text -notmatch 'const advancedTariffPoint='){
  $pattern='const\s+tariffSaving\s*=\s*Number\([\s\S]*?monthly_saving_with_vat\|\|0\);\s*const\s+totalSaving\s*=\s*powerSaving\+reactiveSaving\+tariffSaving;'

  $replacement=@'
const legacyTariffSaving=Number(tariffSavings.find(x=>x.meter_id===selected.meter_id&&String(x.billing_period).slice(0,7)===periodOf(selected))?.monthly_saving_with_vat||0);
  const advancedTariffPoint=advancedTariffHistory?.points.find(x=>String(x.billing_period).slice(0,7)===periodOf(selected));
  const advancedTariffSaving=advancedTariffPoint?.available===false?0:Number(advancedTariffPoint?.monthly_saving||0);
  const tariffSaving=advancedTariffSaving>0?advancedTariffSaving:legacyTariffSaving;
  const tariffSavingSource=advancedTariffSaving>0?"T4":legacyTariffSaving>0?"legacy":"none";
  const totalSaving=powerSaving+reactiveSaving+tariffSaving;
'@

  $new=[regex]::Replace($text,$pattern,$replacement,1)
  if($new -eq $text){
    throw "No pude encontrar el bloque tariffSaving ni siquiera con búsqueda flexible. No hice cambios."
  }
  $text=$new
}

# ---------------------------------------------------------------
# 3) Reconstruir TariffSavingTrend completo
# ---------------------------------------------------------------
$start=$text.IndexOf('function TariffSavingTrend(')
$end=$text.IndexOf('function InvoiceTrend(',$start)
if($start -lt 0 -or $end -lt 0){throw "No encontré TariffSavingTrend/InvoiceTrend."}

$fn=@'
function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string;available?:boolean}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string;available?:boolean}>();
    for(const row of rows){
      const p=String(row.billing_period||"").slice(0,7);
      if(p)map.set(p,row);
    }
    return [...map.entries()]
      .sort((a,b)=>a[0].localeCompare(b[0]))
      .slice(-24)
      .map(([period,row])=>({
        period,
        row,
        value:Math.max(0,Number(row.monthly_saving||0)),
        available:row.available!==false
      }));
  },[rows]);

  if(!data.length){
    return <div className="invoice-tariff-no-data">
      <b>Sin histórico tarifario</b>
      <span>No hay períodos disponibles para este medidor.</span>
    </div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.filter(d=>d.available).map(d=>d.value))*1.08;
  const slot=plotW/Math.max(1,data.length),bw=Math.max(12,slot*.58);

  const axis=(value:number)=>{
    if(value>=1000000)return `$ ${(value/1000000).toLocaleString("es-AR",{maximumFractionDigits:1})} M`;
    if(value>=1000)return `$ ${(value/1000).toLocaleString("es-AR",{maximumFractionDigits:0})} mil`;
    return money.format(value);
  };

  return <div className="invoice-analysis-chart-wrap">
    <svg viewBox={`0 0 ${width} ${height}`} className="invoice-analysis-chart">
      {[0,.25,.5,.75,1].map(step=>{
        const y=top+plotH*(1-step);
        return <g key={step}>
          <line x1={left} x2={width-right} y1={y} y2={y}/>
          <text x={left-10} y={y+4} textAnchor="end">{axis(max*step)}</text>
        </g>
      })}

      {data.map((d,index)=>{
        const x=left+index*slot+(slot-bw)/2;
        const y=top+plotH-(d.value/max)*plotH;
        const missing=!d.available;
        const barY=missing?top+plotH-10:(d.value>0?y:top+plotH-3);
        const barH=missing?10:Math.max(3,top+plotH-y);

        return <g
          className={`invoice-analysis-bar tariff-saving-bar${missing?" missing":""}${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={barY} width={bw} height={barH} rx="5">
            <title>{missing
              ?`${labelPeriod(d.period)} · Falta cuadro tarifario ${d.row.recommended_tariff||"propuesto"}`
              :`${labelPeriod(d.period)} · ${d.row.current_tariff||"Actual"} → ${d.row.recommended_tariff||"Propuesta"} · ${money.format(d.value)}`
            }</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>

    <div className="invoice-tariff-legend">
      <span><i className="saving"/>Ahorro valorizado</span>
      {data.some(d=>!d.available)&&<span><i className="missing"/>Falta cuadro T4 para ese mes</span>}
    </div>
  </div>
}

'@

$text=$text.Substring(0,$start)+$fn+$text.Substring($end)

# ---------------------------------------------------------------
# 4) Agregar available a advancedRows
# ---------------------------------------------------------------
$advPattern='const\s+advancedRows=\(advancedTariffHistory\?\.points\|\|\[\]\)\.map\(x=>\(\{[\s\S]*?recommended_tariff:x\.recommended_tariff[\s\S]*?\}\)\);'
$advReplacement=@'
const advancedRows=(advancedTariffHistory?.points||[]).map(x=>({
            billing_period:String(x.billing_period).slice(0,7),
            monthly_saving:Number(x.monthly_saving||0),
            current_tariff:x.current_tariff,
            recommended_tariff:x.recommended_tariff,
            available:x.available!==false
          }));
'@
$text=[regex]::Replace($text,$advPattern,$advReplacement,1)

# legacyRows: marcar available true
$legacyPattern='const\s+legacyRows=tariffSavings[\s\S]*?\.map\(x=>\(\{[\s\S]*?recommended_tariff:x\.recommended_tariff[\s\S]*?\}\)\);'
$legacyMatch=[regex]::Match($text,$legacyPattern)
if($legacyMatch.Success -and $legacyMatch.Value -notmatch 'available:true'){
  $legacyNew=$legacyMatch.Value -replace 'recommended_tariff:x\.recommended_tariff\s*\}\)', 'recommended_tariff:x.recommended_tariff,'+"`r`n"+'              available:true'+"`r`n"+'            })'
  $text=$text.Substring(0,$legacyMatch.Index)+$legacyNew+$text.Substring($legacyMatch.Index+$legacyMatch.Length)
}

# ---------------------------------------------------------------
# 5) Cuadro inferior: usar el mismo ahorro del gráfico
# ---------------------------------------------------------------
$bottomPattern='<div><span>Encuadramiento tarifario</span><b>\{money\.format\(tariffSaving\)\}</b><small>\{[\s\S]*?</small></div>'
$bottomReplacement='<div><span>Encuadramiento tarifario</span><b>{money.format(tariffSaving)}</b><small>{tariffSavingSource==="T4"?`${advancedTariffPoint?.current_tariff||"Actual"} → ${advancedTariffPoint?.recommended_tariff||"T4"} · simulación antes de impuestos`:tariffSavingSource==="legacy"?"Ahorro mensual simulado con IVA":advancedTariffPoint?.available===false?"Falta cuadro tarifario T4 para este período":"Sin ahorro tarifario valorizado"}</small></div>'
$text=[regex]::Replace($text,$bottomPattern,$bottomReplacement,1)

Set-Content $front $text -Encoding UTF8

# ---------------------------------------------------------------
# 6) CSS
# ---------------------------------------------------------------
$c=Get-Content $css -Raw
if($c -notmatch 'EPEN V11 FIX2'){
Add-Content $css @'

/* EPEN V11 FIX2 */
.tariff-saving-bar.missing rect{fill:#cbd5e1!important;stroke:#94a3b8;stroke-width:1}
.tariff-saving-bar.missing.selected rect{fill:#94a3b8!important;stroke:#475569;stroke-width:2}
.invoice-tariff-legend{display:flex;gap:18px;justify-content:flex-end;padding:2px 26px 0;font-size:11px;color:#475569}
.invoice-tariff-legend span{display:flex;align-items:center;gap:7px}
.invoice-tariff-legend i{width:13px;height:13px;border-radius:4px;display:inline-block}
.invoice-tariff-legend i.saving{background:#2b9b70}
.invoice-tariff-legend i.missing{background:#cbd5e1;border:1px solid #94a3b8}
'@ -Encoding UTF8
}

Write-Host ""
Write-Host "OK - V11 FIX2 aplicada." -ForegroundColor Green
Write-Host "Este fix NO depende del espaciado exacto del archivo." -ForegroundColor Yellow
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Ahora:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
