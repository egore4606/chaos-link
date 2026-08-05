[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'ChaosLink'),
    [switch]$Accept,
    [switch]$SkipFirewallCleanup
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and -not $SkipFirewallCleanup) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Запустите деинсталлятор от имени администратора.'
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-InstallRoot', "`"$InstallRoot`"")
    if ($Accept) { $arguments += '-Accept' }
    if ($SkipFirewallCleanup) { $arguments += '-SkipFirewallCleanup' }
    $process = Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$resolvedRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$volumeRoot = [IO.Path]::GetPathRoot($resolvedRoot).TrimEnd('\')
$protectedRoots = @($volumeRoot, $env:WINDIR, $env:USERPROFILE, $env:LOCALAPPDATA) |
    Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
if ($protectedRoots -contains $resolvedRoot) {
    throw "Отказано в удалении защищённого каталога '$resolvedRoot'."
}
$marker = Join-Path $resolvedRoot '.chaos-link-install'
if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
    throw "Chaos Link не найден в '$resolvedRoot'. Защитная метка отсутствует, поэтому ничего не удалено."
}

Write-Host "Будет полностью удалена установка Chaos Link:" -ForegroundColor Yellow
Write-Host $resolvedRoot
Write-Host 'Будут остановлены агент, сервер и туннель, удалены настройки, скримеры, ярлыки и правило брандмауэра.'
if (-not $Accept -and (Read-Host 'Для удаления введите DELETE') -ne 'DELETE') {
    Write-Host 'Удаление отменено.'
    exit
}

$runtime = Join-Path $resolvedRoot 'runtime'
$allowedExecutables = @(
    (Join-Path $resolvedRoot 'dotnet\dotnet.exe'),
    (Join-Path $resolvedRoot 'tools\cloudflared.exe')
)

foreach ($name in @('agent', 'tunnel', 'server', 'console')) {
    $pidFile = Join-Path $runtime "$name.pid"
    if (-not (Test-Path -LiteralPath $pidFile)) { continue }
    $storedPid = 0
    if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw), [ref]$storedPid) -and $storedPid -ne $PID) {
        $process = Get-Process -Id $storedPid -ErrorAction SilentlyContinue
        if ($process) {
            $processPath = $null
            try { $processPath = $process.Path } catch {}
            if ($allowedExecutables -contains $processPath) {
                Stop-Process -Id $storedPid -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# PID files can be stale or absent after an interrupted shutdown. As a fallback,
# stop only executables physically located inside this verified installation.
Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    $processPath = $null
    try { $processPath = $_.Path } catch {}
    if ($allowedExecutables -contains $processPath -and $_.Id -ne $PID) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

$portableAhk = Join-Path $resolvedRoot 'tools\AutoHotkey64.exe'
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | ForEach-Object {
    $processPath = $null
    try { $processPath = $_.Path } catch {}
    if ($processPath -eq $portableAhk) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

if (-not $SkipFirewallCleanup) {
    Get-NetFirewallRule -DisplayName 'Chaos Link LAN' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

$shortcutShell = New-Object -ComObject WScript.Shell
$desktop = $shortcutShell.SpecialFolders.Item('Desktop')
if (-not [string]::IsNullOrWhiteSpace($desktop)) {
    foreach ($name in @(
        'Chaos Link - Start.lnk', 'Chaos Link - Stop.lnk', 'Chaos Link - Files.lnk', 'Chaos Link - Uninstall.lnk',
        'Chaos Link - Запустить.lnk', 'Chaos Link - Остановить.lnk', 'Chaos Link - Удалить.lnk'
    )) {
        Remove-Item -LiteralPath (Join-Path $desktop $name) -Force -ErrorAction SilentlyContinue
    }
}

$cleanupScript = Join-Path $env:TEMP ("ChaosLinkCleanup-" + [Guid]::NewGuid().ToString('N') + '.ps1')
$cleanup = @'
param([int]$ParentPid, [string]$InstallRoot, [string]$CleanupScript)
Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot '.chaos-link-install'))) { break }
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $InstallRoot)) { break }
    Start-Sleep -Milliseconds 500
}
Remove-Item -LiteralPath $CleanupScript -Force -ErrorAction SilentlyContinue
'@
Set-Content -LiteralPath $cleanupScript -Value $cleanup -Encoding utf8
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cleanupScript`"",
    '-ParentPid', $PID, '-InstallRoot', "`"$resolvedRoot`"", '-CleanupScript', "`"$cleanupScript`""
) | Out-Null

Write-Host 'Chaos Link остановлен. После закрытия этого окна папка установки будет удалена.' -ForegroundColor Green
if (-not $Accept) { Read-Host 'Нажмите Enter, чтобы закрыть окно' }
