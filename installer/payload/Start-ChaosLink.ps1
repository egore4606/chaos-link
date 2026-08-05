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
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

function Stop-StartedProcess($process, $pidFile) {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

$managedNames = if ($ReuseTunnel) { @('server') } else { @('server', 'tunnel') }
foreach ($name in $managedNames) {
    $pidFile = Join-Path $runtime "$name.pid"
    if (Test-Path $pidFile) {
        $oldId = [int](Get-Content $pidFile -Raw)
        if (Get-Process -Id $oldId -ErrorAction SilentlyContinue) {
            throw "Chaos Link уже запущен. Сначала используйте ярлык остановки."
        }
        Remove-Item $pidFile -Force
    }
}

$server = $null
$tunnel = $null
$serverPidFile = Join-Path $runtime 'server.pid'
$tunnelPidFile = Join-Path $runtime 'tunnel.pid'
try {
    $server = Start-Process -FilePath $dotnet `
        -ArgumentList @($serverDll, '--urls', "http://0.0.0.0:$Port") `
        -WorkingDirectory (Join-Path $root 'app\server') `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $runtime 'server.out.log') `
        -RedirectStandardError (Join-Path $runtime 'server.err.log') `
        -PassThru
    Set-Content $serverPidFile $server.Id -Encoding ascii

    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $health = Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 2
            if ($health.status -eq 'ok') { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
    if (-not $ready) { throw 'Сервер не запустился. Проверьте runtime\server.err.log.' }

    $publicUrl = $null
    if ($ReuseTunnel) {
        $accessBeforeRestart = Get-Content (Join-Path $runtime 'access.json') -Raw | ConvertFrom-Json
        $publicUrl = $accessBeforeRestart.PublicUrl
    } else {
        $tunnelOut = Join-Path $runtime 'tunnel.out.log'
        $tunnelErr = Join-Path $runtime 'tunnel.err.log'
        $tunnel = Start-Process -FilePath $cloudflared `
            -ArgumentList @('tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$Port") `
            -WorkingDirectory $root `
            -WindowStyle Hidden `
            -RedirectStandardOutput $tunnelOut `
            -RedirectStandardError $tunnelErr `
            -PassThru
        Set-Content $tunnelPidFile $tunnel.Id -Encoding ascii

        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $text = ((Get-Content $tunnelOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $tunnelErr -Raw -ErrorAction SilentlyContinue))
            if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $publicUrl = $Matches[0]; break }
            if ($tunnel.HasExited) { break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $publicUrl) { throw 'Cloudflare Tunnel не выдал ссылку. Проверьте runtime\tunnel.err.log.' }
    }

    & (Join-Path $root 'Start-AgentAdmin.ps1') -Port $Port
} catch {
    Stop-StartedProcess $tunnel $tunnelPidFile
    Stop-StartedProcess $server $serverPidFile
    throw
}

$accessPath = Join-Path $runtime 'access.json'
$access = Get-Content $accessPath -Raw | ConvertFrom-Json
$access | Add-Member -NotePropertyName PublicUrl -NotePropertyValue $publicUrl -Force
$access | ConvertTo-Json | Set-Content $accessPath -Encoding utf8

Clear-Host
Write-Host 'CHAOS LINK ЗАПУЩЕН' -ForegroundColor Green
Write-Host "Сайт: $publicUrl"
Write-Host "Комната: $($access.RoomCode)"
Write-Host "Ключ гостей: $($access.ControllerToken)"
Write-Host "Ключ администратора: $($access.AdminToken)"
Write-Host ''
Write-Host 'Скопируйте эти данные друзьям. Это окно можно закрыть.'
Read-Host 'Нажмите Enter'
