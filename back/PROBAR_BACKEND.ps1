$ErrorActionPreference = "Stop"
try {
  $result = Invoke-RestMethod -Uri "http://localhost:8000/health"
  Write-Host "Backend funcionando correctamente:" -ForegroundColor Green
  $result | ConvertTo-Json
} catch {
  Write-Host "No se pudo conectar. Verifica que INICIAR_BACKEND.ps1 siga abierto." -ForegroundColor Red
}
