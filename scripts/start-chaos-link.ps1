[CmdletBinding()]
param(
    [int]$Port = 5075,
    [string]$BindAddress = '0.0.0.0',
    [switch]$SkipAgent
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$deployRoot = Join-Path $projectRoot 'deploy'
$runtimeRoot = Join-Path $projectRoot '.runtime'
$serverDll = Join-Path $deployRoot 'server\ChaosLink.Server.dll'

if (-not (Test-Path -LiteralPath $serverDll)) {
    throw 'Deploy-сборка не найдена. Сначала запустите scripts\publish-chaos-link.ps1.'
}

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

$portProbe = [Net.Sockets.TcpClient]::new()
try {
    $connectTask = $portProbe.ConnectAsync('127.0.0.1', $Port)
    if ($connectTask.Wait(300) -and $portProbe.Connected) {
        throw "Порт $Port уже занят. Остановите текущий процесс или выберите другой порт."
    }
} catch [AggregateException] {
    # Connection refused means the port is available.
} finally {
    $portProbe.Dispose()
}

$serverOut = Join-Path $runtimeRoot 'server.out.log'
$serverErr = Join-Path $runtimeRoot 'server.err.log'
$server = Start-Process -FilePath 'dotnet' `
    -ArgumentList "`"$serverDll`"", '--urls', "http://${BindAddress}:$Port" `
    -WorkingDirectory (Join-Path $deployRoot 'server') `
    -WindowStyle Hidden `
    -RedirectStandardOutput $serverOut `
    -RedirectStandardError $serverErr `
    -PassThru

Set-Content -LiteralPath (Join-Path $runtimeRoot 'server.pid') -Value $server.Id -Encoding ascii

Start-Sleep -Seconds 1
if ($server.HasExited) {
    $details = Get-Content -LiteralPath $serverErr -Raw -ErrorAction SilentlyContinue
    throw "Chaos Link server не запустился. $details"
}
$health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 5

if (-not $SkipAgent) {
    & (Join-Path $PSScriptRoot 'start-agent-admin.ps1') -Port $Port
    $agentPidFile = Join-Path $runtimeRoot 'agent.pid'
    $agent = $null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-Path -LiteralPath $agentPidFile) {
            $agentPid = [int](Get-Content -LiteralPath $agentPidFile -Raw)
            $agent = Get-Process -Id $agentPid -ErrorAction SilentlyContinue
            if ($agent) { break }
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $agent) {
        Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
        $details = Get-Content -LiteralPath (Join-Path $runtimeRoot 'agent.err.log') -Raw -ErrorAction SilentlyContinue
        throw "Chaos Link Agent не запустился. $details"
    }
}

$monitorPidFile = Join-Path $runtimeRoot 'log-monitor.pid'
$monitorRunning = $false
if (Test-Path -LiteralPath $monitorPidFile) {
    $monitorPid = [int](Get-Content -LiteralPath $monitorPidFile -Raw)
    $monitorRunning = [bool](Get-Process -Id $monitorPid -ErrorAction SilentlyContinue)
}
if (-not $monitorRunning) {
    $monitor = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'watch-chaos-link.ps1')`"") `
        -WorkingDirectory $projectRoot `
        -PassThru
    Set-Content -LiteralPath $monitorPidFile -Value $monitor.Id -Encoding ascii
}

Write-Host "Chaos Link запущен: http://127.0.0.1:$Port"
Write-Host "Локальная сеть: http://<IP-этого-компьютера>:$Port"
Write-Host "Reverse proxy upstream: http://127.0.0.1:$Port"
Write-Host "Комната: $($health.room)"
