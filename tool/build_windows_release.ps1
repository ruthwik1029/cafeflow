<#
.SYNOPSIS
  Builds the CafeFlow Windows Release Binary and Inno Setup Installer.
.DESCRIPTION
  Compiles the release Windows desktop runner, bundles Flutter runtime assets,
  and packages everything into build\installer\CafeFlow-Setup-1.0.0.exe.
#>
param(
    [string]$Flutter = "flutter",
    [string]$IsccPath = "iscc"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CafeFlow Windows Release & Installer Builder" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Workspace: $root"

Push-Location $root
try {
    # 1. Validate Flutter
    Write-Host "[1/4] Checking Flutter installation..." -ForegroundColor Yellow
    $flutterCmd = Get-Command $Flutter -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        Write-Error "Flutter SDK not found on PATH."
        exit 1
    }

    # 2. Validate Inno Setup
    Write-Host "[2/4] Checking Inno Setup Compiler (iscc)..." -ForegroundColor Yellow
    $isccCmd = Get-Command $IsccPath -ErrorAction SilentlyContinue
    if (-not $isccCmd) {
        # Check standard installation locations
        $standardPaths = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
        )
        foreach ($p in $standardPaths) {
            if (Test-Path $p) {
                $isccCmd = Get-Item $p
                break
            }
        }
    }
    if (-not $isccCmd) {
        Write-Error "Inno Setup 6 compiler (iscc) not found. Please install Inno Setup 6 or add it to PATH."
        exit 1
    }
    $isccDisplay = if ($isccCmd.FullName) { $isccCmd.FullName } else { $isccCmd.Source }
    Write-Host "      Found Inno Setup: $isccDisplay" -ForegroundColor Green

    # 3. Build Windows Release
    Write-Host "[3/4] Compiling Windows release executable..." -ForegroundColor Yellow
    & $Flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows release build failed."
        exit 1
    }

    $runnerExe = "$root\build\windows\x64\runner\Release\cafeflow.exe"
    if (-not (Test-Path $runnerExe)) {
        Write-Error "Expected runner executable not found at: $runnerExe"
        exit 1
    }
    Write-Host "      Compiled runner: $runnerExe" -ForegroundColor Green

    # 4. Compile Installer
    Write-Host "[4/4] Compiling Inno Setup installer..." -ForegroundColor Yellow
    $issScript = "$root\windows\installer\cafeflow_installer.iss"
    if (-not (Test-Path $issScript)) {
        Write-Error "Installer script not found at: $issScript"
        exit 1
    }

    New-Item -ItemType Directory -Force "$root\build\installer" | Out-Null
    & $isccCmd "$issScript"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup compilation failed."
        exit 1
    }

    $installerExe = "$root\build\installer\CafeFlow-Setup-1.0.0.exe"
    if (Test-Path $installerExe) {
        $sizeMb = [math]::Round((Get-Item $installerExe).Length / 1MB, 2)
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "  SUCCESS: Windows Installer Compiled Successfully!" -ForegroundColor Green
        Write-Host "  Installer: $installerExe" -ForegroundColor Green
        Write-Host "  File Size: $sizeMb MB" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
    } else {
        Write-Error "Installer executable not found at expected location: $installerExe"
        exit 1
    }
}
finally {
    Pop-Location
}
