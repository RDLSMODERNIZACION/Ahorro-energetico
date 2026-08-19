$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
Write-Host "Instalando backend de Gestion Energetica Municipal..." -ForegroundColor Green
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Host "Python no esta instalado o no esta agregado al PATH." -ForegroundColor Red
  Read-Host "Presiona ENTER para cerrar"; exit 1
}
if (-not (Test-Path ".venv")) { python -m venv .venv }
& ".\.venv\Scripts\python.exe" -m pip install --upgrade pip
& ".\.venv\Scripts\python.exe" -m pip install -r requirements.txt
if (-not (Test-Path ".env")) {
  Copy-Item ".env.example" ".env"
  Write-Host "Se creo .env. Pegale la Secret Key de Supabase antes de iniciar." -ForegroundColor Yellow
}
Write-Host "Instalacion terminada." -ForegroundColor Green
Read-Host "Presiona ENTER para cerrar"
