[CmdletBinding()]
param()

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator) {
    $elevated = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") `
        -Verb RunAs `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    exit $elevated.ExitCode
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot '.runtime'

$monitorPidFile = Join-Path $runtimeRoot 'log-monitor.pid'
if (Test-Path -LiteralPath $monitorPidFile) {
    $monitorPid = [int](Get-Content -LiteralPath $monitorPidFile -Raw)
    $monitorProcess = Get-Process -Id $monitorPid -ErrorAction SilentlyContinue
    if ($monitorProcess -and $monitorProcess.ProcessName -in @('pwsh', 'powershell')) {
        Stop-Process -Id $monitorPid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $monitorPidFile -Force -ErrorAction SilentlyContinue
}

foreach ($name in @('agent', 'server')) {
    $pidFile = Join-Path $runtimeRoot "$name.pid"
    if (-not (Test-Path -LiteralPath $pidFile)) { continue }

    $processId = [int](Get-Content -LiteralPath $pidFile -Raw)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -eq 'dotnet') {
        Stop-Process -Id $processId
        Write-Host "$name остановлен (PID $processId)."
    }
    Remove-Item -LiteralPath $pidFile -Force
}
