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
$backup="$path.bak-v13-parse-$stamp"
Copy-Item $path $backup -Force

$text=Get-Content $path -Raw

$bad=@'
        )}
            onPeriod={setSelectedPeriod}
          />
        )}
      </section>
'@

$good=@'
        )}
      </section>
'@

if($text.Contains($bad)){
    $text=$text.Replace($bad,$good)
} else {
    # fallback: eliminar únicamente el duplicado que aparece entre el cierre
    # del ternario y </section>
    $pattern='\)\}\s*onPeriod=\{setSelectedPeriod\}\s*/>\s*\)\}\s*</section>'
    $replacement=')}'+"`r`n"+'      </section>'
    $new=[regex]::Replace($text,$pattern,$replacement,1)
    if($new -eq $text){
        throw "No encontré el duplicado exacto de V13. No hice cambios."
    }
    $text=$new
}

Set-Content $path $text -Encoding UTF8

Write-Host ""
Write-Host "OK - parse error V13 corregido." -ForegroundColor Green
Write-Host "Se eliminó el bloque duplicado después de InvoiceTrend." -ForegroundColor Yellow
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Ahora:" -ForegroundColor Cyan
Write-Host "  cd front"
Write-Host "  npm run dev"
