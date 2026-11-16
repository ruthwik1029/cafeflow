<#
.SYNOPSIS
  Builds the CafeFlow Android Release APK and Distribution Bundle.
.DESCRIPTION
  Compiles the release Android APK for POS tablet / mobile distribution,
  and copies it to build\installer\CafeFlow-Android-1.0.0.apk.
#>
param(
    [string]$Flutter = "flutter",
    [switch]$AppBundle
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CafeFlow Android Release Builder" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Workspace: $root"

Push-Location $root
try {
    # 1. Check signing configuration
    $keyProps = "$root\android\key.properties"
    if (Test-Path $keyProps) {
        Write-Host "[1/3] Using production upload keystore configured in android/key.properties." -ForegroundColor Green
    } else {
        Write-Host "[1/3] Note: android/key.properties not found. Building with debug signing fallback." -ForegroundColor Yellow
        Write-Host "      This produces a valid, installable APK for demo testing and hardware sideloading." -ForegroundColor Gray
    }

    # 2. Compile APK / AAB using tool/build_android.ps1
    Write-Host "[2/3] Executing Android Gradle compilation..." -ForegroundColor Yellow
    $buildScript = "$root\tool\build_android.ps1"
    if ($AppBundle) {
        & $buildScript -Flutter $Flutter -AppBundle
    } else {
        & $buildScript -Flutter $Flutter
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Android build script failed."
        exit 1
    }

    # 3. Copy to standard distribution path
    Write-Host "[3/3] Preparing distribution release asset..." -ForegroundColor Yellow
    $sourceApk = "$root\build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $sourceApk) {
        New-Item -ItemType Directory -Force "$root\build\installer" | Out-Null
        $destApk = "$root\build\installer\CafeFlow-Android-1.0.0.apk"
        Copy-Item -Path $sourceApk -Destination $destApk -Force
        Copy-Item -Path $sourceApk -Destination "$root\build\app\outputs\flutter-apk\CafeFlow-Android-1.0.0.apk" -Force

        $sizeMb = [math]::Round((Get-Item $destApk).Length / 1MB, 2)
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "  SUCCESS: Android Release APK Ready!" -ForegroundColor Green
        Write-Host "  Distribution APK: $destApk" -ForegroundColor Green
        Write-Host "  File Size: $sizeMb MB" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
    } else {
        Write-Error "Release APK not found at: $sourceApk"
        exit 1
    }
}
finally {
    Pop-Location
}

