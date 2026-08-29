[CmdletBinding()]
param([int]$Port = 5075)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Port', $Port) `
        -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Запуск игрового агента отменён или завершился ошибкой.' }
    return
}

$root = $PSScriptRoot
$runtime = Join-Path $root 'runtime'
$agentExe = Join-Path $root 'app\agent\ChaosLink.Agent.exe'
$serverExe = Join-Path $root 'app\server\ChaosLink.Server.exe'

$rule = Get-NetFirewallRule -DisplayName 'Chaos Link LAN' -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName 'Chaos Link LAN' -Direction Inbound -Action Allow `
        -Program $serverExe -Protocol TCP -LocalPort $Port -Profile Private -RemoteAddress LocalSubnet | Out-Null
}

$agent = Start-Process -FilePath $agentExe `
    -WorkingDirectory (Join-Path $root 'app\agent') `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $runtime 'agent.out.log') `
    -RedirectStandardError (Join-Path $runtime 'agent.err.log') `
    -PassThru
Set-Content (Join-Path $runtime 'agent.pid') $agent.Id -Encoding ascii
Start-Sleep -Seconds 1
if ($agent.HasExited) { throw 'Агент не запустился. Проверьте runtime\agent.err.log.' }
