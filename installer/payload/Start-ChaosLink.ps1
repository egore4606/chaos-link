[CmdletBinding()]
param(
    [int]$Port = 5075,
    [switch]$ReuseTunnel
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$runtime = Join-Path $root 'runtime'
$dotnet = Join-Path $root 'dotnet\dotnet.exe'
$serverDll = Join-Path $root 'app\server\ChaosLink.Server.dll'
$cloudflared = Join-Path $root 'tools\cloudflared.exe'
$serverPidFile = Join-Path $runtime 'server.pid'
$tunnelPidFile = Join-Path $runtime 'tunnel.pid'
$agentPidFile = Join-Path $runtime 'agent.pid'
$accessPath = Join-Path $runtime 'access.json'
$tunnelOut = Join-Path $runtime 'tunnel.out.log'
$tunnelErr = Join-Path $runtime 'tunnel.err.log'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

function Get-TrackedProcess([string]$pidFile) {
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }
    try {
        $trackedId = [int](Get-Content -LiteralPath $pidFile -Raw)
        $process = Get-Process -Id $trackedId -ErrorAction SilentlyContinue
        if ($process) { return $process }
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
    $server = Get-TrackedProcess $serverPidFile
    $health = if ($server) { Wait-ForServer } else { $null }
    if ($server -and -not $health) {
        Write-Host 'Найден зависший сервер. Перезапускаю его...' -ForegroundColor Yellow
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $serverPidFile -Force -ErrorAction SilentlyContinue
        $server = $null
    }
    if (-not $server) {
        Write-Host 'Запуск локального сервера...'
        $startedServer = Start-Process -FilePath $dotnet `
            -ArgumentList @($serverDll, '--urls', "http://0.0.0.0:$Port") `
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

    $tunnel = Get-TrackedProcess $tunnelPidFile
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

    # Save the URL before UAC so a later interruption cannot lose it.
    $access = Save-PublicUrl $publicUrl
    Write-Host "HTTPS-туннель готов: $publicUrl" -ForegroundColor Green

    $agent = Get-TrackedProcess $agentPidFile
    if ($agent) {
        Write-Host 'Игровой агент уже запущен — повторный запуск не нужен.' -ForegroundColor DarkGray
    } else {
        Write-Host 'Сейчас появится запрос Windows. Нажмите «Да» для запуска игрового агента.' -ForegroundColor Yellow
        & (Join-Path $root 'Start-AgentAdmin.ps1') -Port $Port
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

Clear-Host
Write-Host 'CHAOS LINK ЗАПУЩЕН' -ForegroundColor Green
Write-Host "Сайт: $publicUrl"
Write-Host "Комната: $($access.RoomCode)"
Write-Host "Ключ гостей: $($access.ControllerToken)"
Write-Host "Ключ администратора: $($access.AdminToken)"
Write-Host ''
Write-Host 'Скопируйте эти данные друзьям. Это окно можно закрыть.'
Read-Host 'Нажмите Enter'
