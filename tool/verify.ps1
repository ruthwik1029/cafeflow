param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    New-Item -ItemType Directory -Force artifacts/verification | Out-Null
    $checks = @(
        @{ Name = 'analyze'; Arguments = @('analyze') },
        @{ Name = 'test'; Arguments = @('test') },
        @{ Name = 'windows'; Arguments = @('build', 'windows') },
        @{ Name = 'android'; Arguments = @('build', 'apk', '--release', '-t', 'lib/main_android.dart') },
        @{ Name = 'web'; Arguments = @('build', 'web') }
    )
    $results = @()
    foreach ($check in $checks) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $arguments = $check.Arguments
        if ($check.Name -eq 'android') {
            & "$PSScriptRoot/build_android.ps1" -Flutter $Flutter 2>&1 | Tee-Object -FilePath "artifacts/verification/$($check.Name).log"
        } else {
            & $Flutter @arguments 2>&1 | Tee-Object -FilePath "artifacts/verification/$($check.Name).log"
        }
        $code = $LASTEXITCODE
        $watch.Stop()
        $results += [pscustomobject]@{ Check = $check.Name; ExitCode = $code; Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 2) }
        $results | ConvertTo-Json | Set-Content -Encoding utf8 artifacts/verification/results.json
        if ($code -ne 0 -and $check.Name -in @('analyze', 'test')) {
            throw "Foundation check failed: $($check.Name). See artifacts/verification."
        }
    }
    $results | Format-Table -AutoSize
    if ($results.ExitCode | Where-Object { $_ -ne 0 }) { exit 1 }
} finally { Pop-Location }
