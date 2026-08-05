[CmdletBinding()]
param([int]$Port = 5075)

$ErrorActionPreference = 'Stop'
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Port', $Port) `
        -Verb RunAs `
        -WindowStyle Hidden | Out-Null
    return
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$deployRoot = Join-Path $projectRoot 'deploy'
$runtimeRoot = Join-Path $projectRoot '.runtime'
$agentDll = Join-Path $deployRoot 'agent\ChaosLink.Agent.dll'

$firewallRule = Get-NetFirewallRule -DisplayName 'Chaos Link LAN' -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule -DisplayName 'Chaos Link LAN' -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $Port -Profile Private -RemoteAddress LocalSubnet | Out-Null
}

$agentOut = Join-Path $runtimeRoot 'agent.out.log'
$agentErr = Join-Path $runtimeRoot 'agent.err.log'
$agent = Start-Process -FilePath 'dotnet' `
    -ArgumentList "`"$agentDll`"" `
    -WorkingDirectory (Join-Path $deployRoot 'agent') `
    -WindowStyle Hidden `
    -RedirectStandardOutput $agentOut `
    -RedirectStandardError $agentErr `
    -PassThru

Set-Content -LiteralPath (Join-Path $runtimeRoot 'agent.pid') -Value $agent.Id -Encoding ascii
Start-Sleep -Seconds 1
if ($agent.HasExited) {
    $details = Get-Content -LiteralPath $agentErr -Raw -ErrorAction SilentlyContinue
    throw "Chaos Link Agent не запустился. $details"
}
