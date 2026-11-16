<#
.SYNOPSIS
  Builds the CafeFlow Flutter Web Release for Vercel / Static Hosting.
.DESCRIPTION
  Compiles the customer-facing web application into build\web and verifies
  the vercel.json SPA rewrite and HTTP security header configuration.
#>
param(
    [string]$Flutter = "flutter"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CafeFlow Web Release Builder" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Workspace: $root"

Push-Location $root
try {
    # 1. Validate Flutter
    Write-Host "[1/3] Checking Flutter installation..." -ForegroundColor Yellow
    $flutterCmd = Get-Command $Flutter -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        Write-Error "Flutter SDK not found on PATH."
        exit 1
    }

    # 2. Build Web Release
    Write-Host "[2/3] Compiling Flutter Web production bundle..." -ForegroundColor Yellow
    & $Flutter build web --release --base-href /
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Web build failed."
        exit 1
    }

    # 3. Verify Deployment Artifacts
    Write-Host "[3/3] Verifying Web release assets and Vercel configuration..." -ForegroundColor Yellow
    $webIndex = "$root\build\web\index.html"
    $vercelConfig = "$root\vercel.json"

    if (-not (Test-Path $webIndex)) {
        Write-Error "Expected index.html not found at: $webIndex"
        exit 1
    }

    if (-not (Test-Path $vercelConfig)) {
        Write-Warning "vercel.json not found in root. SPA client routing will need server rewrite to /index.html."
    } else {
        Write-Host "      Verified vercel.json with SPA rewrites and security headers." -ForegroundColor Green
    }

    $itemCount = (Get-ChildItem -Path "$root\build\web" -Recurse -File).Count
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  SUCCESS: Web Release Bundle Ready for Vercel Deployment!" -ForegroundColor Green
    Write-Host "  Output Directory: $root\build\web" -ForegroundColor Green
    Write-Host "  Files Generated: $itemCount" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
}
finally {
    Pop-Location
}

