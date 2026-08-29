[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '0.6.1'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'payload'
$dependencyCache = Join-Path $dist 'dependency-cache'

$autoHotkeyVersion = '2.0.26'
$autoHotkeySha256 = '43522AA3122A57784AC5DB30ABF85C2244475C36ACD7796E2C993355F9E926AE'
$cloudflaredVersion = '2026.5.2'
$cloudflaredSha256 = '20B9638F685333D623798E733EFFBAD2487093F15BA592F6C7752360FF3B7AB7'

function Invoke-Native {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Команда завершилась с кодом $LASTEXITCODE`: $FilePath $Arguments" }
}

function Get-VerifiedFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Sha256
    )
    if (Test-Path -LiteralPath $Destination) {
        $existingHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($existingHash -eq $Sha256) {
            Write-Host "Использую проверенный кэш: $Destination"
            return
        }
        Remove-Item -LiteralPath $Destination -Force
    }

    $partial = "$Destination.partial"
    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $partial -UseBasicParsing -TimeoutSec 180
        $actualHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
        if ($actualHash -ne $Sha256) {
            throw "Контрольная сумма не совпала для $Uri. Ожидалась $Sha256, получена $actualHash."
        }
        Move-Item -LiteralPath $partial -Destination $Destination -Force
    } finally {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dist, $dependencyCache,
    (Join-Path $stage 'app\server'),
    (Join-Path $stage 'app\agent'),
    (Join-Path $stage 'app\control'),
    (Join-Path $stage 'ahk'),
    (Join-Path $stage 'tools'),
    (Join-Path $stage 'screamer\images'),
    (Join-Path $stage 'screamer\sounds') | Out-Null

Push-Location (Join-Path $root 'apps\web')
try { Invoke-Native 'npm.cmd' 'run' 'build' } finally { Pop-Location }

$publishOptions = @('-c', 'Release', '-r', 'win-x64', '--self-contained', 'true',
    '-p:DebugType=None', '-p:DebugSymbols=false')
Invoke-Native 'dotnet.exe' 'publish' (Join-Path $root 'apps\server\ChaosLink.Server.csproj') '-o' (Join-Path $stage 'app\server') @publishOptions
Invoke-Native 'dotnet.exe' 'publish' (Join-Path $root 'apps\agent\ChaosLink.Agent.csproj') '-o' (Join-Path $stage 'app\agent') @publishOptions
Invoke-Native 'dotnet.exe' 'publish' (Join-Path $root 'apps\control\ChaosLink.Control.csproj') '-o' (Join-Path $stage 'app\control') @publishOptions

Copy-Item -LiteralPath (Join-Path $root 'ahk\Effects.ahk') -Destination (Join-Path $stage 'ahk\Effects.ahk') -Force
Copy-Item -Path (Join-Path $root 'installer\payload\*.ps1') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root 'scripts\control-chaos-link.ps1') -Destination (Join-Path $stage 'Control-ChaosLink.ps1') -Force
Copy-Item -LiteralPath (Join-Path $root 'screamer\images\README.md') -Destination (Join-Path $stage 'screamer\images\README.md') -Force
Copy-Item -LiteralPath (Join-Path $root 'screamer\sounds\README.md') -Destination (Join-Path $stage 'screamer\sounds\README.md') -Force
Copy-Item -LiteralPath (Join-Path $root 'installer\THIRD_PARTY_NOTICES.md') -Destination (Join-Path $stage 'THIRD_PARTY_NOTICES.md') -Force

# Windows PowerShell 5.1 interprets UTF-8 without BOM as the current ANSI code page.
# Preserve Russian diagnostics and parser behavior on every Windows locale.
$utf8Bom = [Text.UTF8Encoding]::new($true)
Get-ChildItem -LiteralPath $stage -Recurse -Filter *.ps1 | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8
    [IO.File]::WriteAllText($_.FullName, $content, $utf8Bom)
}

$autoHotkeyZip = Join-Path $dependencyCache "AutoHotkey_$autoHotkeyVersion.zip"
Get-VerifiedFile -Uri "https://github.com/AutoHotkey/AutoHotkey/releases/download/v$autoHotkeyVersion/AutoHotkey_$autoHotkeyVersion.zip" `
    -Destination $autoHotkeyZip -Sha256 $autoHotkeySha256
$autoHotkeyExtract = Join-Path $dependencyCache "AutoHotkey_$autoHotkeyVersion"
if (Test-Path -LiteralPath $autoHotkeyExtract) { Remove-Item -LiteralPath $autoHotkeyExtract -Recurse -Force }
Expand-Archive -LiteralPath $autoHotkeyZip -DestinationPath $autoHotkeyExtract -Force
$autoHotkeyExe = Get-ChildItem -LiteralPath $autoHotkeyExtract -Recurse -Filter AutoHotkey64.exe | Select-Object -First 1
if (-not $autoHotkeyExe) { throw 'AutoHotkey64.exe отсутствует в проверенном архиве.' }
Copy-Item -LiteralPath $autoHotkeyExe.FullName -Destination (Join-Path $stage 'tools\AutoHotkey64.exe') -Force

$cloudflaredCache = Join-Path $dependencyCache "cloudflared-windows-amd64-$cloudflaredVersion.exe"
Get-VerifiedFile -Uri "https://github.com/cloudflare/cloudflared/releases/download/$cloudflaredVersion/cloudflared-windows-amd64.exe" `
    -Destination $cloudflaredCache -Sha256 $cloudflaredSha256
Copy-Item -LiteralPath $cloudflaredCache -Destination (Join-Path $stage 'tools\cloudflared.exe') -Force

$manifest = [ordered]@{
    productVersion = $Version
    runtimeIdentifier = 'win-x64'
    dotnet = 'self-contained'
    autoHotkey = @{ version = $autoHotkeyVersion; sha256 = $autoHotkeySha256.ToLowerInvariant() }
    cloudflared = @{ version = $cloudflaredVersion; sha256 = $cloudflaredSha256.ToLowerInvariant() }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'BUILD-MANIFEST.json') -Encoding utf8

$isccCandidates = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $isccCandidates) {
    throw 'Inno Setup Compiler (ISCC.exe) не найден. Установите Inno Setup 6.7+ и повторите сборку.'
}

$installerPath = Join-Path $dist 'ChaosLink-Setup.exe'
Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
Invoke-Native $isccCandidates "/DAppVersion=$Version" "/DStageDir=$stage" (Join-Path $root 'installer\ChaosLink.iss')
if (-not (Test-Path -LiteralPath $installerPath)) { throw 'Inno Setup не создал ChaosLink-Setup.exe.' }

if ($env:CHAOS_LINK_SIGNING_THUMBPRINT) {
    & (Join-Path $root 'scripts\sign-release.ps1') -CertificateThumbprint $env:CHAOS_LINK_SIGNING_THUMBPRINT -Files $installerPath
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось подписать установщик.' }
} else {
    Write-Warning 'Установщик не подписан: переменная CHAOS_LINK_SIGNING_THUMBPRINT не задана.'
}

$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'), "$hash  ChaosLink-Setup.exe`n", [Text.UTF8Encoding]::new($false))
Write-Host "Готовый офлайн-установщик: $installerPath"
Write-Host "SHA-256: $hash"
