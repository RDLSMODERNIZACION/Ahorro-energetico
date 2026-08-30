$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$file = Join-Path $repo "front\app\public-lighting-panel.tsx"

if(-not (Test-Path $file)){
    throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $file "$file.bak-$stamp" -Force

$text = Get-Content $file -Raw -Encoding UTF8

# 1) Agregar estado de orden
$anchor = '  const [selected,setSelected]=useState<PLRow|null>(null);'
if(-not $text.Contains($anchor)){
    throw "No encontré el estado selected."
}

$replacement = @'
  const [selected,setSelected]=useState<PLRow|null>(null);
  const [sortKey,setSortKey]=useState<"consumption"|"amount"|null>(null);
  const [sortDir,setSortDir]=useState<"desc"|"asc">("desc");
'@

$text = $text.Replace($anchor,$replacement)

# 2) Reemplazar cálculo rows para incluir ordenamiento
$pattern = 'const rows=useMemo\(\(\)=>\{[\s\S]*?\},\[data,search,status\]\);'

$rowsReplacement = @'
const rows=useMemo(()=>{
    if(!data)return[];

    const q=search.trim().toLowerCase();

    const filtered=data.rows.filter(row=>{
      if(status!=="all"&&row.analysis_status!==status)return false;
      if(!q)return true;

      return [row.meter_number,row.supply_number,row.supply_contract,row.address,row.invoice_number]
        .some(v=>String(v||"").toLowerCase().includes(q));
    });

    if(!sortKey)return filtered;

    return [...filtered].sort((a,b)=>{
      const av=sortKey==="consumption"
        ? Number(a.active_energy_kwh??-1)
        : Number(a.total_amount??-1);

      const bv=sortKey==="consumption"
        ? Number(b.active_energy_kwh??-1)
        : Number(b.total_amount??-1);

      return sortDir==="desc" ? bv-av : av-bv;
    });
  },[data,search,status,sortKey,sortDir]);

  function toggleSort(key:"consumption"|"amount"){
    if(sortKey===key){
      setSortDir(current=>current==="desc"?"asc":"desc");
    }else{
      setSortKey(key);
      setSortDir("desc");
    }
  }
'@

$rx = [regex]::new($pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
if(-not $rx.IsMatch($text)){
    throw "No encontré el bloque rows=useMemo esperado."
}
$text = $rx.Replace($text,$rowsReplacement,1)

# 3) Reemplazar encabezados Consumo / Importe por botones clickeables
$oldConsumption = '<span>CONSUMO</span>'
$newConsumption = @'
<button
            type="button"
            className={`pl-sort-head ${sortKey==="consumption"?"active":""}`}
            onClick={()=>toggleSort("consumption")}
            title="Ordenar por consumo"
          >
            CONSUMO {sortKey==="consumption"?(sortDir==="desc"?"↓":"↑"):""}
          </button>
'@

if(-not $text.Contains($oldConsumption)){
    throw "No encontré encabezado CONSUMO."
}
$text = $text.Replace($oldConsumption,$newConsumption)

$oldAmount = '<span>IMPORTE</span>'
$newAmount = @'
<button
            type="button"
            className={`pl-sort-head ${sortKey==="amount"?"active":""}`}
            onClick={()=>toggleSort("amount")}
            title="Ordenar por importe"
          >
            IMPORTE {sortKey==="amount"?(sortDir==="desc"?"↓":"↑"):""}
          </button>
'@

if(-not $text.Contains($oldAmount)){
    throw "No encontré encabezado IMPORTE."
}
$text = $text.Replace($oldAmount,$newAmount)

Set-Content $file -Value $text -Encoding UTF8

Write-Host ""
Write-Host "Ordenamiento de AP aplicado." -ForegroundColor Green
Write-Host ""
Write-Host "Ahora podés hacer click en:" -ForegroundColor Cyan
Write-Host "  - CONSUMO"
Write-Host "  - IMPORTE"
Write-Host ""
Write-Host "Primer click: mayor a menor"
Write-Host "Segundo click: menor a mayor"
Write-Host ""
Write-Host "Backup: $file.bak-$stamp"
