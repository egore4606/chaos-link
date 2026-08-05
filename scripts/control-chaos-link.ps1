[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('restart', 'shutdown')]
    [string]$Action,
    [int]$Port = 5075
)

$ErrorActionPreference = 'Stop'
$installedLayout = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Start-ChaosLink.ps1')
$scriptRoot = if ($installedLayout) { $PSScriptRoot } else { Split-Path -Parent $PSScriptRoot }
$startScript = if ($installedLayout) { Join-Path $scriptRoot 'Start-ChaosLink.ps1' } else { Join-Path $PSScriptRoot 'start-chaos-link.ps1' }
$stopScript = if ($installedLayout) { Join-Path $scriptRoot 'Stop-ChaosLink.ps1' } else { Join-Path $PSScriptRoot 'stop-chaos-link.ps1' }

# The elevated agent launches this helper, then exits. Give it time to release its files.
Start-Sleep -Milliseconds 700

if ($installedLayout) {
    $runtime = Join-Path $scriptRoot 'runtime'
    foreach ($name in @('agent', 'server')) {
        $pidFile = Join-Path $runtime "$name.pid"
        if (-not (Test-Path -LiteralPath $pidFile)) { continue }
        $processId = [int](Get-Content -LiteralPath $pidFile -Raw)
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
} else {
    & $stopScript
}

if ($Action -eq 'shutdown') { exit 0 }

for ($attempt = 0; $attempt -lt 40; $attempt++) {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) { break }
    Start-Sleep -Milliseconds 250
}

if ($installedLayout) {
    $consolePidFile = Join-Path $scriptRoot 'runtime\console.pid'
    $consoleRunning = $false
    if (Test-Path -LiteralPath $consolePidFile) {
        $consoleId = [int](Get-Content -LiteralPath $consolePidFile -Raw)
        $consoleProcess = Get-Process -Id $consoleId -ErrorAction SilentlyContinue
        $consolePath = if ($consoleProcess) { try { $consoleProcess.Path } catch { $null } } else { $null }
        $expectedDotNet = Join-Path $scriptRoot 'dotnet\dotnet.exe'
        $consoleRunning = $consolePath -and $consolePath.Equals($expectedDotNet, [StringComparison]::OrdinalIgnoreCase)
    }
    & $startScript -Port $Port -ReuseTunnel -SkipConsole:$consoleRunning
} else {
    & $startScript -Port $Port
}
