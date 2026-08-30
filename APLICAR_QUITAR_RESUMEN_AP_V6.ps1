$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$file = Join-Path $repo "front\app\public-lighting-panel.tsx"

if(-not (Test-Path $file)){
    throw "No encontré $file. Ejecutá este script desde la raíz de Ahorro-energetico."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $file "$file.bak-$stamp" -Force

$text = Get-Content $file -Raw -Encoding UTF8

$pattern = '<section\s+className="panel\s+pl-summary-strip">[\s\S]*?</section>'
$rx = [regex]::new($pattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)

if(-not $rx.IsMatch($text)){
    throw "No encontré el bloque pl-summary-strip en public-lighting-panel.tsx."
}

$text = $rx.Replace($text,"",1)
Set-Content $file -Value $text -Encoding UTF8

Write-Host ""
Write-Host "Resumen superior de Alumbrado Público eliminado." -ForegroundColor Green
Write-Host ""
Write-Host "Se quitó:" -ForegroundColor Cyan
Write-Host "  - Consumo del mes"
Write-Host "  - Importe facturado"
Write-Host "  - Promedio por factura"
Write-Host "  - Cobertura"
Write-Host ""
Write-Host "Backup creado: $file.bak-$stamp"
