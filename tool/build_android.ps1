param(
    [string]$Flutter = 'flutter',
    [switch]$VerboseBuild,
    [switch]$AppBundle
)

$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskSocketDirectory = Join-Path $taskRoot 'build/java-sockets'
$taskPreviousJavaOptions = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'Process')
$taskExitCode = 1

# Java 25's selector uses Unix-domain wakeup sockets. On this Windows host,
# sockets under the inherited TEMP directory fail even though TCP works.
# Scope only the socket location to this build; retain the installed JDK and
# default selector, and preserve any existing JVM options.
New-Item -ItemType Directory -Force -Path $taskSocketDirectory | Out-Null
$taskSocketOption = '"-Djdk.net.unixdomain.tmpdir=' + $taskSocketDirectory + '"'
Push-Location $taskRoot
try {
    [Environment]::SetEnvironmentVariable(
        'JAVA_TOOL_OPTIONS',
        ($taskPreviousJavaOptions + ' ' + $taskSocketOption).Trim(),
        'Process'
    )
    $targetFormat = if ($AppBundle) { 'appbundle' } else { 'apk' }
    $taskArguments = @('build', $targetFormat, '--release', '-t', 'lib/main_android.dart')
    if ($VerboseBuild) { $taskArguments += '-v' }
    & $Flutter @taskArguments
    $taskExitCode = $LASTEXITCODE
} finally {
    if ($null -eq $taskPreviousJavaOptions) {
        # PowerShell can coerce a null String argument into an empty value.
        # Restore an absent variable as absent, not as an empty environment entry.
        Remove-Item -LiteralPath Env:JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $taskPreviousJavaOptions, 'Process')
    }
    Pop-Location
}

exit $taskExitCode
