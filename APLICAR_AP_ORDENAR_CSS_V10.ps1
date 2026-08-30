$ErrorActionPreference = "Stop"

$repo = (Get-Location).Path
$file = Join-Path $repo "front\app\public-lighting-panel.css"

if(-not (Test-Path $file)){
    throw "No encontré $file."
}

$marker = "/* AP sort headers */"
$text = Get-Content $file -Raw -Encoding UTF8

if($text -notmatch [regex]::Escape($marker)){
    Add-Content $file "`r`n" -Encoding UTF8
    Add-Content $file (Get-Content (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ap-sort.css") -Raw -Encoding UTF8) -Encoding UTF8
}

Write-Host "CSS de ordenamiento aplicado." -ForegroundColor Green
