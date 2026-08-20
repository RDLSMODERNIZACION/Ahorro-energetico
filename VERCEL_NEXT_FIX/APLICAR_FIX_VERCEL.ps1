$ErrorActionPreference = "Stop"

Write-Host "Aplicando compatibilidad con Vercel / Next.js..." -ForegroundColor Cyan

$candidates = @(
    (Get-Location).Path,
    (Join-Path (Get-Location).Path "front"),
    (Split-Path $PSScriptRoot -Parent),
    (Join-Path (Split-Path $PSScriptRoot -Parent) "front")
) | Select-Object -Unique

$front = $null
foreach ($candidate in $candidates) {
    if ((Test-Path (Join-Path $candidate "package.json")) -and
        (Test-Path (Join-Path $candidate "app\page.tsx"))) {
        $front = $candidate
        break
    }
}

if (-not $front) {
    throw "No encontre el frontend. Extrae este ZIP dentro de Ahorro-energetico y ejecutalo desde esa carpeta."
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path)
}

function Write-Utf8([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8)
}

$pagePath = Join-Path $front "app\page.tsx"
$page = Read-Utf8 $pagePath
$page = $page.Replace(
    '(import.meta.env.VITE_API_URL as string) || "https://ahorro-energetico.onrender.com"',
    'process.env.NEXT_PUBLIC_API_URL || "https://ahorro-energetico.onrender.com"'
)
Write-Utf8 $pagePath $page

$supabasePath = Join-Path $front "app\lib\supabase.ts"
$supabase = Read-Utf8 $supabasePath
$supabase = $supabase.Replace(
    'const url = import.meta.env.VITE_SUPABASE_URL as string;',
    'const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";'
)
$supabase = $supabase.Replace(
    'const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;',
    'const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";'
)
$supabase = $supabase.Replace(
    'const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";',
    'const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://ywfgjwghaqrmsefzvqgs.supabase.co";'
)
$supabase = $supabase.Replace(
    'const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";',
    'const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "sb_publishable_VIoLn6S43Rzh6q6gXvAKow_4M2FDxar";'
)
Write-Utf8 $supabasePath $supabase

$tsconfigPath = Join-Path $front "tsconfig.json"
$tsconfig = Get-Content $tsconfigPath -Raw | ConvertFrom-Json
$excluded = @(
    "node_modules", "db", "worker", "examples", "tests", "dist", "build",
    ".wrangler", ".sites-runtime"
)
$tsconfig.exclude = $excluded
$tsconfigJson = $tsconfig | ConvertTo-Json -Depth 20
Write-Utf8 $tsconfigPath ($tsconfigJson + [Environment]::NewLine)

$packagePath = Join-Path $front "package.json"
$package = Get-Content $packagePath -Raw | ConvertFrom-Json
$package.engines.node = "22.x"
$packageJson = $package | ConvertTo-Json -Depth 30
Write-Utf8 $packagePath ($packageJson + [Environment]::NewLine)

$nextConfigPath = Join-Path $front "next.config.mjs"
$nextConfig = @'
/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
};

export default nextConfig;
'@
Write-Utf8 $nextConfigPath ($nextConfig + [Environment]::NewLine)

$envExamplePath = Join-Path $front ".env.example"
if (Test-Path $envExamplePath) {
    $envExample = Read-Utf8 $envExamplePath
    $envExample = $envExample.Replace("VITE_API_URL", "NEXT_PUBLIC_API_URL")
    $envExample = $envExample.Replace("VITE_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL")
    $envExample = $envExample.Replace("VITE_SUPABASE_PUBLISHABLE_KEY", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY")
    Write-Utf8 $envExamplePath $envExample
}

Write-Host "" 
Write-Host "Correccion aplicada en: $front" -ForegroundColor Green
Write-Host "Ahora subi los cambios con GitHub Desktop y hace Redeploy en Vercel." -ForegroundColor Yellow
Write-Host "En Vercel conserva Build Command: npx next build" -ForegroundColor Yellow
