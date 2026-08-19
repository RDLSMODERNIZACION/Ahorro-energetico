$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
if (-not (Test-Path ".venv\Scripts\python.exe")) {
  Write-Host "Primero ejecuta INSTALAR_BACKEND.ps1" -ForegroundColor Red
  Read-Host "Presiona ENTER para cerrar"; exit 1
}
if (-not (Test-Path ".env")) {
  Write-Host "Falta el archivo .env" -ForegroundColor Red
  Read-Host "Presiona ENTER para cerrar"; exit 1
}
Write-Host "Backend iniciado en http://localhost:8000" -ForegroundColor Green
Write-Host "Documentacion: http://localhost:8000/docs" -ForegroundColor Cyan
& ".\.venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
