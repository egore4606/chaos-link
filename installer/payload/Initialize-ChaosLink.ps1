[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$logPath = Join-Path $env:TEMP 'ChaosLink-install-bootstrap.log'

try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
} catch {
    # Inno Setup keeps its own early log. Transcript failure must not block install.
}

function Write-JsonAtomic {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $temporary = "$Path.new"
    $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function New-HexToken([int]$ByteCount) {
    $buffer = New-Object byte[] $ByteCount
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($buffer) } finally { $generator.Dispose() }
    return ([BitConverter]::ToString($buffer) -replace '-', '').ToLowerInvariant()
}

function New-RoomCode {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $buffer = New-Object byte[] 4
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($buffer) } finally { $generator.Dispose() }
    return -join ($buffer | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

try {
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $required = @(
        'app\server\ChaosLink.Server.exe',
        'app\agent\ChaosLink.Agent.exe',
        'app\control\ChaosLink.Control.exe',
        'tools\AutoHotkey64.exe',
        'tools\cloudflared.exe',
        'ahk\Effects.ahk',
        'Start-ChaosLink.ps1',
        'Stop-ChaosLink.ps1'
    )
    foreach ($relativePath in $required) {
        $path = Join-Path $InstallRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Установочный пакет повреждён: отсутствует $relativePath"
        }
    }

    $runtime = Join-Path $InstallRoot 'runtime'
    New-Item -ItemType Directory -Force -Path $runtime,
        (Join-Path $InstallRoot 'screamer\images'),
        (Join-Path $InstallRoot 'screamer\sounds') | Out-Null

    $serverConfigPath = Join-Path $InstallRoot 'app\server\appsettings.Production.json'
    $accessPath = Join-Path $runtime 'access.json'
    $room = $null
    $controllerToken = $null
    $adminToken = $null
    $agentToken = $null

    if ((Test-Path -LiteralPath $serverConfigPath) -and (Test-Path -LiteralPath $accessPath)) {
        try {
            $oldServer = Get-Content -LiteralPath $serverConfigPath -Raw | ConvertFrom-Json
            $oldAccess = Get-Content -LiteralPath $accessPath -Raw | ConvertFrom-Json
            $room = [string]$oldAccess.RoomCode
            $controllerToken = [string]$oldAccess.ControllerToken
            $adminToken = [string]$oldAccess.AdminToken
            $agentToken = [string]$oldServer.ChaosLink.AgentToken
        } catch {
            Write-Warning 'Старые настройки повреждены; будут созданы новые безопасные ключи.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($room)) { $room = New-RoomCode }
    if ([string]::IsNullOrWhiteSpace($controllerToken)) { $controllerToken = New-HexToken 18 }
    if ([string]::IsNullOrWhiteSpace($adminToken)) { $adminToken = New-HexToken 18 }
    if ([string]::IsNullOrWhiteSpace($agentToken)) { $agentToken = New-HexToken 24 }

    Write-JsonAtomic -Path $serverConfigPath -Value @{
        ChaosLink = @{
            RoomCode = $room
            ControllerToken = $controllerToken
            AdminToken = $adminToken
            AgentToken = $agentToken
            ExecutionLeadMs = 250
        }
    }

    Write-JsonAtomic -Path (Join-Path $InstallRoot 'app\agent\appsettings.json') -Value @{
        ServerUrl = 'ws://127.0.0.1:5075/ws'
        RoomCode = $room
        AgentName = 'Игровой ПК'
        AgentToken = $agentToken
        AutoHotkeyPath = (Join-Path $InstallRoot 'tools\AutoHotkey64.exe')
        EffectsScript = '..\..\ahk\Effects.ahk'
        ScreamerSoundsPath = '..\..\screamer\sounds'
        ScreamerImagesPath = '..\..\screamer\images'
        HostControlScript = '..\..\Control-ChaosLink.ps1'
    }

    $publicUrl = $null
    if (Test-Path -LiteralPath $accessPath) {
        try { $publicUrl = (Get-Content -LiteralPath $accessPath -Raw | ConvertFrom-Json).PublicUrl } catch {}
    }
    $access = @{
        RoomCode = $room
        ControllerToken = $controllerToken
        AdminToken = $adminToken
        LocalUrl = 'http://127.0.0.1:5075'
    }
    if (-not [string]::IsNullOrWhiteSpace($publicUrl)) { $access['PublicUrl'] = $publicUrl }
    Write-JsonAtomic -Path $accessPath -Value $access
    Set-Content -LiteralPath (Join-Path $InstallRoot '.chaos-link-install') -Value 'Chaos Link managed installation' -Encoding ascii
    Copy-Item -LiteralPath $logPath -Destination (Join-Path $runtime 'install-bootstrap.log') -Force -ErrorAction SilentlyContinue
} catch {
    Write-Error $_
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
