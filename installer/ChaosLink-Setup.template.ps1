[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'ChaosLink'),
    [switch]$Accept,
    [switch]$SkipStart,
    [switch]$SkipShortcuts
)

$ErrorActionPreference = 'Stop'
Write-Host 'Chaos Link устанавливает локальный игровой агент удалённых эффектов.' -ForegroundColor Yellow
Write-Host 'После запуска люди с ключом смогут посылать разрешённые нажатия клавиш, движения мыши и экранные эффекты.'
Write-Host 'Автозапуск и скрытая служба НЕ устанавливаются. Для работы используется Cloudflare Quick Tunnel.'
if (-not $Accept -and (Read-Host 'Для добровольной установки введите INSTALL') -ne 'INSTALL') { Write-Host 'Отменено.'; exit }

$payloadBase64 = '__CHAOS_LINK_PAYLOAD__'
$tempRoot = Join-Path $env:TEMP ("ChaosLinkSetup-" + [Guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'payload.zip'
New-Item -ItemType Directory -Force -Path $tempRoot, $InstallRoot | Out-Null

try {
    [IO.File]::WriteAllBytes($zipPath, [Convert]::FromBase64String($payloadBase64))
    Expand-Archive -LiteralPath $zipPath -DestinationPath $InstallRoot -Force

    $dotnetRoot = Join-Path $InstallRoot 'dotnet'
    if (-not (Test-Path (Join-Path $dotnetRoot 'dotnet.exe'))) {
        Write-Host 'Установка .NET 9 Runtime...'
        $dotnetInstall = Join-Path $tempRoot 'dotnet-install.ps1'
        Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -UseBasicParsing -OutFile $dotnetInstall
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dotnetInstall -Channel 9.0 -Runtime aspnetcore -InstallDir $dotnetRoot -NoPath
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить .NET Runtime.' }
    }

    $tools = Join-Path $InstallRoot 'tools'
    New-Item -ItemType Directory -Force -Path $tools | Out-Null
    $ahkPath = Join-Path $tools 'AutoHotkey64.exe'
    if (-not (Test-Path $ahkPath)) {
        Write-Host 'Установка AutoHotkey 2.0.26...'
        $ahkZip = Join-Path $tempRoot 'autohotkey.zip'
        Invoke-WebRequest 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip' -UseBasicParsing -OutFile $ahkZip
        $actualHash = (Get-FileHash $ahkZip -Algorithm SHA256).Hash
        if ($actualHash -ne '43522AA3122A57784AC5DB30ABF85C2244475C36ACD7796E2C993355F9E926AE') { throw 'Контрольная сумма AutoHotkey не совпала.' }
        $ahkExtract = Join-Path $tempRoot 'ahk'
        Expand-Archive $ahkZip $ahkExtract -Force
        $ahkExe = Get-ChildItem $ahkExtract -Recurse -Filter AutoHotkey64.exe | Select-Object -First 1
        if (-not $ahkExe) { throw 'AutoHotkey64.exe отсутствует в архиве.' }
        Copy-Item $ahkExe.FullName $ahkPath -Force
    }

    $cloudflared = Join-Path $tools 'cloudflared.exe'
    if (-not (Test-Path $cloudflared)) {
        Write-Host 'Установка Cloudflare Tunnel...'
        Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -UseBasicParsing -OutFile $cloudflared
    }

    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    function New-Token([int]$bytes) {
        $buffer = New-Object byte[] $bytes
        $rng.GetBytes($buffer)
        return ([BitConverter]::ToString($buffer) -replace '-', '').ToLowerInvariant()
    }
    $room = -join ((1..4) | ForEach-Object { 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[(Get-Random -Maximum 32)] })
    $controllerToken = New-Token 18
    $adminToken = New-Token 18
    $agentToken = New-Token 24

    $serverConfig = @{ ChaosLink = @{ RoomCode=$room; ControllerToken=$controllerToken; AdminToken=$adminToken; AgentToken=$agentToken; ExecutionLeadMs=250 } } | ConvertTo-Json -Depth 4
    Set-Content (Join-Path $InstallRoot 'app\server\appsettings.Production.json') $serverConfig -Encoding utf8
    $agentConfig = @{
        ServerUrl='ws://127.0.0.1:5075/ws'; RoomCode=$room; AgentName='Игровой ПК'; AgentToken=$agentToken
        AutoHotkeyPath=$ahkPath; EffectsScript='..\..\ahk\Effects.ahk'
        ScreamerSoundsPath='..\..\screamer\sounds'; ScreamerImagesPath='..\..\screamer\images'
        HostControlScript='..\..\Control-ChaosLink.ps1'
    } | ConvertTo-Json
    Set-Content (Join-Path $InstallRoot 'app\agent\appsettings.json') $agentConfig -Encoding utf8
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot 'runtime'), (Join-Path $InstallRoot 'screamer\images'), (Join-Path $InstallRoot 'screamer\sounds') | Out-Null
    Set-Content (Join-Path $InstallRoot '.chaos-link-install') 'Chaos Link managed installation' -Encoding ascii
    @{ RoomCode=$room; ControllerToken=$controllerToken; AdminToken=$adminToken; LocalUrl='http://127.0.0.1:5075' } | ConvertTo-Json | Set-Content (Join-Path $InstallRoot 'runtime\access.json') -Encoding utf8

    if (-not $SkipShortcuts) {
        $shell = New-Object -ComObject WScript.Shell
        $desktop = $shell.SpecialFolders.Item('Desktop')
        if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
            Write-Warning 'Папка рабочего стола недоступна. Установка продолжена без ярлыков.'
        } else {
            foreach ($item in @(
                @{ Name='Chaos Link - Запустить.lnk'; Script='Start-ChaosLink.ps1' },
                @{ Name='Chaos Link - Остановить.lnk'; Script='Stop-ChaosLink.ps1' },
                @{ Name='Chaos Link - Удалить.lnk'; Script='Uninstall-ChaosLink.ps1' }
            )) {
                try {
                    $shortcut = $shell.CreateShortcut((Join-Path $desktop $item.Name))
                    $shortcut.TargetPath = 'powershell.exe'
                    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallRoot $item.Script)`""
                    $shortcut.WorkingDirectory = $InstallRoot
                    $shortcut.Save()
                } catch {
                    Write-Warning "Не удалось создать ярлык '$($item.Name)': $($_.Exception.Message)"
                }
            }
        }
    }
} finally {
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Chaos Link установлен: $InstallRoot" -ForegroundColor Green
if (-not $SkipStart) {
    Write-Host 'Сейчас будет создан публичный HTTPS-туннель и появится один запрос администратора.'
    & (Join-Path $InstallRoot 'Start-ChaosLink.ps1')
}
