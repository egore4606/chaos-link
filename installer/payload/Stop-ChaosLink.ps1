[CmdletBinding()]
param([switch]$RemoveFirewallRule)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($RemoveFirewallRule) { $arguments += '-RemoveFirewallRule' }
    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $arguments `
        -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

$runtime = Join-Path $PSScriptRoot 'runtime'
$expectedExecutables = @{
    agent = Join-Path $PSScriptRoot 'app\agent\ChaosLink.Agent.exe'
    server = Join-Path $PSScriptRoot 'app\server\ChaosLink.Server.exe'
    console = Join-Path $PSScriptRoot 'app\control\ChaosLink.Control.exe'
    tunnel = Join-Path $PSScriptRoot 'tools\cloudflared.exe'
}
foreach ($name in @('agent', 'tunnel', 'server', 'console')) {
    $pidFile = Join-Path $runtime "$name.pid"
    if (-not (Test-Path $pidFile)) { continue }
    $processId = [int](Get-Content $pidFile -Raw)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    $processPath = if ($process) { try { $process.Path } catch { $null } } else { $null }
    if ($processPath -and $processPath.Equals($expectedExecutables[$name], [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
if ($RemoveFirewallRule) {
    Get-NetFirewallRule -DisplayName 'Chaos Link LAN' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}
Write-Host 'Chaos Link остановлен.'
