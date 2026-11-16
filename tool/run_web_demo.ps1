<#
.SYNOPSIS
  Runs the CafeFlow Customer Website Demo in Google Chrome.
.DESCRIPTION
  Validates prerequisites and serves the public customer-facing cafe storefront
  on http://localhost:8080 with isolated public routing and demo menu catalog.
#>
param(
    [string]$Flutter = "flutter",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CafeFlow Public Customer Website Demo Launcher" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Workspace: $root"

# 1. Check Flutter prerequisite
Write-Host "[1/3] Validating Flutter installation..." -ForegroundColor Yellow
$flutterCmd = Get-Command $Flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Error "Flutter SDK not found on PATH. Please install Flutter or provide -Flutter 'path/to/flutter'."
    exit 1
}
Write-Host "      Found Flutter: $($flutterCmd.Source)" -ForegroundColor Green

# 2. Check Web support
Write-Host "[2/3] Checking Flutter Web platform configuration..." -ForegroundColor Yellow
Push-Location $root
try {
    & $Flutter config --enable-web | Out-Null
    Write-Host "      Flutter Web enabled." -ForegroundColor Green

    # 3. Launch Web in Chrome
    Write-Host "[3/3] Launching Customer Storefront on http://localhost:$Port..." -ForegroundColor Yellow
    Write-Host "      Running public portal (internal staff/POS routes isolated)..." -ForegroundColor Gray
    & $Flutter run -d chrome -t lib/main_public.dart --web-port=$Port
}
catch {
    Write-Error "Failed to launch Web demo: $_"
    exit 1
}
finally {
    Pop-Location
}

