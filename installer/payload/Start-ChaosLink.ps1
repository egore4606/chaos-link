[CmdletBinding()]
param(
    [int]$Port = 5075,
    [switch]$ReuseTunnel,
    [switch]$SkipConsole,
    [switch]$ElevatedAgent
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$runtime = Join-Path $root 'runtime'
$serverExe = Join-Path $root 'app\server\ChaosLink.Server.exe'
$agentExe = Join-Path $root 'app\agent\ChaosLink.Agent.exe'
$controlExe = Join-Path $root 'app\control\ChaosLink.Control.exe'
$cloudflared = Join-Path $root 'tools\cloudflared.exe'
$serverPidFile = Join-Path $runtime 'server.pid'
$tunnelPidFile = Join-Path $runtime 'tunnel.pid'
$agentPidFile = Join-Path $runtime 'agent.pid'
$consolePidFile = Join-Path $runtime 'console.pid'
$accessPath = Join-Path $runtime 'access.json'
$tunnelOut = Join-Path $runtime 'tunnel.out.log'
$tunnelErr = Join-Path $runtime 'tunnel.err.log'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$startupLog = Join-Path $runtime 'startup.log'
try { Start-Transcript -LiteralPath $startupLog -Append | Out-Null } catch {}

function Get-TrackedProcess([string]$pidFile, [string]$expectedExecutable) {
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }
    try {
        $trackedId = [int](Get-Content -LiteralPath $pidFile -Raw)
        $process = Get-Process -Id $trackedId -ErrorAction SilentlyContinue
        $actualPath = if ($process) { try { $process.Path } catch { $null } } else { $null }
        if ($actualPath -and $actualPath.Equals($expectedExecutable, [StringComparison]::OrdinalIgnoreCase)) { return $process }
    } catch {}
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Wait-ForServer {
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $health = Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 2
            if ($health.status -eq 'ok') { return $health }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Find-PublicUrl {
    if (Test-Path -LiteralPath $accessPath) {
        try {
            $saved = Get-Content -LiteralPath $accessPath -Raw | ConvertFrom-Json
            if ($saved.PublicUrl -match '^https://[a-z0-9-]+\.trycloudflare\.com/?$') {
                return $Matches[0].TrimEnd('/')
            }
        } catch {}
    }

    $text = ''
    foreach ($logPath in @($tunnelOut, $tunnelErr)) {
        if (Test-Path -LiteralPath $logPath) {
            $text += "`n" + (Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue)
        }
    }
    if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') { return $Matches[0] }
    return $null
}

function Save-PublicUrl([string]$url) {
    $access = Get-Content -LiteralPath $accessPath -Raw | ConvertFrom-Json
    $access | Add-Member -NotePropertyName PublicUrl -NotePropertyValue $url -Force
    $access | ConvertTo-Json | Set-Content -LiteralPath $accessPath -Encoding utf8
    return $access
}

$startedServer = $null
$startedTunnel = $null
try {
    $server = Get-TrackedProcess $serverPidFile $serverExe
    $health = if ($server) { Wait-ForServer } else { $null }
    if ($server -and -not $health) {
        Write-Host 'Найден зависший сервер. Перезапускаю его...' -ForegroundColor Yellow
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $serverPidFile -Force -ErrorAction SilentlyContinue
        $server = $null
    }
    if (-not $server) {
        Write-Host 'Запуск локального сервера...'
        $startedServer = Start-Process -FilePath $serverExe `
            -ArgumentList @('--urls', "http://0.0.0.0:$Port") `
            -WorkingDirectory (Join-Path $root 'app\server') `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $runtime 'server.out.log') `
            -RedirectStandardError (Join-Path $runtime 'server.err.log') `
            -PassThru
        Set-Content -LiteralPath $serverPidFile -Value $startedServer.Id -Encoding ascii
        $health = Wait-ForServer
    } else {
        Write-Host 'Локальный сервер уже запущен — использую его.' -ForegroundColor DarkGray
    }
    if (-not $health) { throw 'Сервер не запустился. Проверьте runtime\server.err.log.' }

    $tunnel = Get-TrackedProcess $tunnelPidFile $cloudflared
    $publicUrl = if ($tunnel) { Find-PublicUrl } else { $null }
    if ($tunnel) {
        Write-Host 'HTTPS-туннель уже запущен — восстанавливаю публичную ссылку.' -ForegroundColor DarkGray
    } else {
        Write-Host 'Создание публичного HTTPS-туннеля Cloudflare...'
        Remove-Item -LiteralPath $tunnelOut, $tunnelErr -Force -ErrorAction SilentlyContinue
        $startedTunnel = Start-Process -FilePath $cloudflared `
            -ArgumentList @('tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$Port") `
            -WorkingDirectory $root `
            -WindowStyle Hidden `
            -RedirectStandardOutput $tunnelOut `
            -RedirectStandardError $tunnelErr `
            -PassThru
        Set-Content -LiteralPath $tunnelPidFile -Value $startedTunnel.Id -Encoding ascii
        $tunnel = $startedTunnel
    }

    Write-Host 'Ожидание публичной ссылки...'
    for ($attempt = 0; -not $publicUrl -and $attempt -lt 90; $attempt++) {
        $publicUrl = Find-PublicUrl
        if (-not $publicUrl -and $tunnel.HasExited) { break }
        if (-not $publicUrl) { Start-Sleep -Milliseconds 500 }
    }
    if (-not $publicUrl) { throw 'Cloudflare Tunnel не выдал ссылку. Проверьте runtime\tunnel.err.log.' }

    # Save the URL before starting the agent so a later interruption cannot lose it.
    $access = Save-PublicUrl $publicUrl
    Write-Host "HTTPS-туннель готов: $publicUrl" -ForegroundColor Green

    $agent = Get-TrackedProcess $agentPidFile $agentExe
    if ($agent) {
        Write-Host 'Игровой агент уже запущен — повторный запуск не нужен.' -ForegroundColor DarkGray
    } elseif ($ElevatedAgent) {
        Write-Host 'Запрошен повышенный режим агента. Подтвердите запрос Windows.' -ForegroundColor Yellow
        & (Join-Path $root 'Start-AgentAdmin.ps1') -Port $Port
    } else {
        Write-Host 'Запуск игрового агента...'
        $startedAgent = Start-Process -FilePath $agentExe `
            -WorkingDirectory (Join-Path $root 'app\agent') `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $runtime 'agent.out.log') `
            -RedirectStandardError (Join-Path $runtime 'agent.err.log') `
            -PassThru
        Set-Content -LiteralPath $agentPidFile -Value $startedAgent.Id -Encoding ascii
        Start-Sleep -Seconds 1
        if ($startedAgent.HasExited) {
            Remove-Item -LiteralPath $agentPidFile -Force -ErrorAction SilentlyContinue
            throw 'Агент не запустился. Проверьте runtime\agent.err.log и runtime\startup.log.'
        }
    }
} catch {
    if ($startedTunnel -and -not $startedTunnel.HasExited) {
        Stop-Process -Id $startedTunnel.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tunnelPidFile -Force -ErrorAction SilentlyContinue
    }
    if ($startedServer -and -not $startedServer.HasExited) {
        Stop-Process -Id $startedServer.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $serverPidFile -Force -ErrorAction SilentlyContinue
    }
    throw
}

Write-Host 'CHAOS LINK ЗАПУЩЕН' -ForegroundColor Green
Write-Host "Сайт: $publicUrl"
Write-Host "Комната: $($access.RoomCode)"
Write-Host "Ключ гостей: $($access.ControllerToken)"
Write-Host "Ключ администратора: $($access.AdminToken)"
Write-Host ''
Write-Host 'Ниже откроется постоянная консоль логов и управления.'
if ($SkipConsole) { return }

$existingConsole = Get-TrackedProcess $consolePidFile $controlExe
if ($existingConsole) {
    Write-Host 'Консоль управления уже открыта.' -ForegroundColor DarkGray
    return
}

if (-not (Test-Path -LiteralPath $controlExe)) {
    throw 'Консоль управления не найдена. Переустановите Chaos Link.'
}

$control = Start-Process -FilePath $controlExe `
    -ArgumentList @('--root', $root) `
    -WorkingDirectory $root `
    -NoNewWindow `
    -PassThru
Set-Content -LiteralPath $consolePidFile -Value $control.Id -Encoding ascii
try {
    Wait-Process -Id $control.Id
} finally {
    Remove-Item -LiteralPath $consolePidFile -Force -ErrorAction SilentlyContinue
}
