<#
.SYNOPSIS
  Safely resets the CafeFlow Demo Environment and Local Storage.
.DESCRIPTION
  Provides a safe, documented procedure to reset demo datasets.
  IMPORTANT: Never automatically deletes or modifies an active production database.
#>
param(
    [switch]$ClearLocalCache,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CafeFlow Demo Data Reset Utility" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Workspace: $root"
Write-Host ""
Write-Host "CafeFlow operates in a safe demonstration mode using fictional data." -ForegroundColor Yellow
Write-Host "All transactions, payments, and accounts are simulated." -ForegroundColor Yellow
Write-Host ""

# 1. Reset In-Memory Demo Data (In Application)
Write-Host "--- 1. In-Application Demo Reset ---" -ForegroundColor Cyan
Write-Host "In the running Windows Desktop or Android app:" -ForegroundColor White
Write-Host "  Navigate to: Admin / Owner Workspace -> Settings -> Demo Environment & Data Controls" -ForegroundColor Gray
Write-Host "  Click: 'Reset Demo State'" -ForegroundColor Gray
Write-Host "  This immediately restores the demo catalog, tables, inventory, and orders to baseline." -ForegroundColor Green
Write-Host ""

# 2. Reset Local Terminal Database Cache
Write-Host "--- 2. Local SQLite Terminal Cache ---" -ForegroundColor Cyan
$localDbPaths = @(
    "$env:APPDATA\CafeFlow",
    "$root\artifacts\local_storage"
)

$foundCaches = @()
foreach ($p in $localDbPaths) {
    if (Test-Path $p) {
        $foundCaches += $p
    }
}

if ($foundCaches.Count -gt 0) {
    Write-Host "Found local terminal storage directory at:" -ForegroundColor Yellow
    foreach ($c in $foundCaches) {
        Write-Host "  $c" -ForegroundColor Gray
    }

    if ($ClearLocalCache) {
        $confirm = $true
        if (-not $Force) {
            $response = Read-Host "Are you sure you want to delete local cached offline transactions? (y/N)"
            $confirm = ($response -eq 'y' -or $response -eq 'Y')
        }
        if ($confirm) {
            foreach ($c in $foundCaches) {
                Remove-Item -Path $c -Recurse -Force
                Write-Host "Deleted local cache: $c" -ForegroundColor Green
            }
        } else {
            Write-Host "Operation cancelled. Local cache preserved." -ForegroundColor Gray
        }
    } else {
        Write-Host "To clear local offline cache, run: .\tool\reset_demo_data.ps1 -ClearLocalCache" -ForegroundColor Gray
    }
} else {
    Write-Host "No local SQLite terminal cache found on this machine." -ForegroundColor Green
}
Write-Host ""

# 3. Remote Supabase Staging Seed Reset Instructions
Write-Host "--- 3. Remote Supabase Database Re-Seed ---" -ForegroundColor Cyan
Write-Host "To reset your remote Supabase demo instance to default seed data:" -ForegroundColor White
Write-Host "  1. Open your Supabase Project Dashboard -> SQL Editor." -ForegroundColor Gray
Write-Host "  2. Load the contents of: supabase\seed.sql" -ForegroundColor Gray
Write-Host "  3. Click Run to re-insert standard fictional bistro data." -ForegroundColor Gray
Write-Host "  Note: CafeFlow never executes remote database resets without explicit authorization." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

