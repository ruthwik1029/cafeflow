<#
.SYNOPSIS
  Runs the CafeFlow Windows Desktop Application in Demo Mode.
.DESCRIPTION
  Validates prerequisites and launches the CafeFlow Windows Desktop runner
  with preloaded sample data and simulated payment workflows.
#>
param(
    [string]$Flutter = "flutter"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CafeFlow Windows Desktop Demo Launcher" -ForegroundColor Cyan
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

# 2. Check Windows desktop support
Write-Host "[2/3] Checking Windows desktop platform configuration..." -ForegroundColor Yellow
Push-Location $root
try {
    & $Flutter config --enable-windows-desktop | Out-Null
    Write-Host "      Windows desktop enabled." -ForegroundColor Green

    # 3. Launch Windows app
    Write-Host "[3/3] Launching CafeFlow Desktop..." -ForegroundColor Yellow
    $runArgs = @('run', '-d', 'windows', '-t', 'lib/main_windows.dart')
    if (Test-Path "$root\.env") {
        Write-Host "      Detected .env file. Including configuration..." -ForegroundColor Gray
        $runArgs += '--dart-define-from-file=.env'
    } else {
        $runArgs += '--dart-define=DEMO_MODE=true'
    }
    & $Flutter @runArgs
}
catch {
    Write-Error "Failed to launch Windows application: $_"
    exit 1
}
finally {
    Pop-Location
}

