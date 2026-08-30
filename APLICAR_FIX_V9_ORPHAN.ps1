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

$path=Join-Path $Repo "front\app\invoice-analysis-panel.tsx"
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup="$path.bak-v9-orphan-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

# 1) Eliminar el fragmento huérfano que dejó la V9.
$orphanStart=':{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){'
$start=$text.IndexOf($orphanStart)

if($start -ge 0){
    $invoiceTrend=$text.IndexOf('function InvoiceTrend(',$start)
    if($invoiceTrend -lt 0){
        throw "Encontré el fragmento huérfano pero no InvoiceTrend."
    }

    # Borrar todo el residuo huérfano hasta InvoiceTrend.
    $text=$text.Substring(0,$start)+$text.Substring($invoiceTrend)
}

# 2) Eliminar cualquier TariffSavingTrend completa existente para dejar una sola.
function Remove-NamedFunction {
    param([string]$Source,[string]$Name)

    while($true){
        $needle="function $Name("
        $s=$Source.IndexOf($needle)
        if($s -lt 0){break}

        # Buscar la apertura REAL del cuerpo: "){" posterior al cierre de firma.
        $sigEnd=$Source.IndexOf('){',$s)
        if($sigEnd -lt 0){throw "No pude ubicar el cuerpo de $Name."}
        $brace=$sigEnd+1

        $depth=0
        $quote=[char]0
        $escape=$false
        $i=$brace

        for(;$i -lt $Source.Length;$i++){
            $c=$Source[$i]

            if($quote -ne [char]0){
                if($escape){$escape=$false;continue}
                if($c -eq '\'){$escape=$true;continue}
                if($c -eq $quote){$quote=[char]0;continue}
                continue
            }

            if($c -eq '"' -or $c -eq "'" -or $c -eq '`'){
                $quote=$c
                continue
            }

            if($c -eq '{'){$depth++}
            elseif($c -eq '}'){
                $depth--
                if($depth -eq 0){
                    $end=$i+1
                    while($end -lt $Source.Length -and ($Source[$end] -eq "`r" -or $Source[$end] -eq "`n")){$end++}
                    $Source=$Source.Substring(0,$s)+$Source.Substring($end)
                    break
                }
            }
        }

        if($i -ge $Source.Length){throw "No pude cerrar function $Name."}
    }

    return $Source
}

$text=Remove-NamedFunction -Source $text -Name 'TariffSavingTrend'

# 3) Insertar una única función limpia antes de InvoiceTrend.
$anchor='function InvoiceTrend('
$idx=$text.IndexOf($anchor)
if($idx -lt 0){throw "No encontré InvoiceTrend."}

$fn=@'
function TariffSavingTrend({rows,selectedPeriod,onPeriod}:{rows:{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}[];selectedPeriod:string;onPeriod:(p:string)=>void}){
  const data=useMemo(()=>{
    const map=new Map<string,{billing_period:string;monthly_saving:number;current_tariff?:string;recommended_tariff?:string}>();
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
        value:Math.max(0,Number(row.monthly_saving||0))
      }));
  },[rows]);

  if(!data.length||!data.some(d=>d.value>0)){
    return <div className="invoice-tariff-no-data">
      <b>Sin ahorro tarifario valorizado</b>
      <span>No hay una simulación mensual disponible para este medidor.</span>
    </div>;
  }

  const width=1280,height=330,left=82,right=28,top=25,bottom=52;
  const plotW=width-left-right,plotH=height-top-bottom;
  const max=Math.max(1,...data.map(d=>d.value))*1.08;
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
        return <g
          className={`invoice-analysis-bar tariff-saving-bar${selectedPeriod===d.period?" selected":""}`}
          key={d.period}
          onClick={()=>onPeriod(d.period)}
        >
          <rect x={x} y={d.value>0?y:top+plotH-2} width={bw} height={Math.max(2,top+plotH-y)} rx="5">
            <title>{labelPeriod(d.period)} · {d.row.current_tariff||"Actual"} → {d.row.recommended_tariff||"Propuesta"} · {money.format(d.value)}</title>
          </rect>
          {(index%3===0||index===data.length-1)&&
            <text x={x+bw/2} y={height-22} textAnchor="middle">{labelPeriod(d.period)}</text>}
        </g>
      })}
    </svg>
  </div>
}

'@

$text=$text.Insert($idx,$fn)

# 4) Validaciones básicas antes de guardar.
$count=([regex]::Matches($text,'function TariffSavingTrend\(')).Count
if($count -ne 1){throw "La reparación dejó $count definiciones de TariffSavingTrend."}

if($text.Contains($orphanStart)){throw "Sigue existiendo el fragmento huérfano."}

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - fragmento huérfano de V9 eliminado y TariffSavingTrend reconstruida." -ForegroundColor Green
Write-Host "TariffSavingTrend definiciones: $count"
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Probá ahora:" -ForegroundColor Yellow
Write-Host "  cd front"
Write-Host "  npm run dev"
