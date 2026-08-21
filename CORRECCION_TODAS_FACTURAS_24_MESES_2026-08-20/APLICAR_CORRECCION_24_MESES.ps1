$ErrorActionPreference = "Stop"

$Package = Split-Path -Parent $MyInvocation.MyCommand.Path
$Project = Split-Path -Parent $Package
$Source = Join-Path $Package "payload\back\app\routers\invoices.py"
$Target = Join-Path $Project "back\app\routers\invoices.py"

if (-not (Test-Path -LiteralPath $Source)) {
    throw "No se encontro el archivo de la correccion: $Source"
}

$TargetDirectory = Split-Path -Parent $Target
if (-not (Test-Path -LiteralPath $TargetDirectory)) {
    throw "No se encontro el backend en: $TargetDirectory"
}

$Backup = "$Target.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $Target -Destination $Backup -Force
Copy-Item -LiteralPath $Source -Destination $Target -Force

Write-Host "Correccion aplicada correctamente." -ForegroundColor Green
Write-Host "Archivo actualizado: $Target"
Write-Host "Copia de seguridad: $Backup"
Write-Host "Ahora subi el cambio a GitHub para que Render despliegue la nueva version."
