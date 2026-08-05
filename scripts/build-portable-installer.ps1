[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'payload'
$zip = Join-Path $dist 'payload.zip'
$output = Join-Path $dist 'ChaosLink-Setup.ps1'
$exeOutput = Join-Path $dist 'ChaosLink-Setup.exe'
$uninstallOutput = Join-Path $dist 'ChaosLink-Uninstall.ps1'
$uninstallExeOutput = Join-Path $dist 'ChaosLink-Uninstall.exe'

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'app\server'), (Join-Path $stage 'app\agent'), (Join-Path $stage 'app\control'), (Join-Path $stage 'ahk'), (Join-Path $stage 'screamer\images'), (Join-Path $stage 'screamer\sounds') | Out-Null

Push-Location (Join-Path $root 'apps\web')
try { npm run build } finally { Pop-Location }
dotnet publish (Join-Path $root 'apps\server\ChaosLink.Server.csproj') -c Release -o (Join-Path $stage 'app\server') --no-self-contained
dotnet publish (Join-Path $root 'apps\agent\ChaosLink.Agent.csproj') -c Release -o (Join-Path $stage 'app\agent') --no-self-contained
dotnet publish (Join-Path $root 'apps\control\ChaosLink.Control.csproj') -c Release -o (Join-Path $stage 'app\control') --no-self-contained

Copy-Item (Join-Path $root 'ahk\Effects.ahk') (Join-Path $stage 'ahk\Effects.ahk') -Force
Copy-Item (Join-Path $root 'installer\payload\*.ps1') $stage -Force
Copy-Item (Join-Path $root 'scripts\control-chaos-link.ps1') (Join-Path $stage 'Control-ChaosLink.ps1') -Force
Copy-Item (Join-Path $root 'installer\ChaosLink-Uninstall.ps1') (Join-Path $stage 'Uninstall-ChaosLink.ps1') -Force
Copy-Item (Join-Path $root 'screamer\images\README.md') (Join-Path $stage 'screamer\images\README.md') -Force
Copy-Item (Join-Path $root 'screamer\sounds\README.md') (Join-Path $stage 'screamer\sounds\README.md') -Force

$utf8Bom = [Text.UTF8Encoding]::new($true)
Get-ChildItem $stage -Filter *.ps1 | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    [IO.File]::WriteAllText($_.FullName, $content, $utf8Bom)
}

if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
$template = Get-Content (Join-Path $root 'installer\ChaosLink-Setup.template.ps1') -Raw
if (-not $template.Contains('__CHAOS_LINK_PAYLOAD__')) { throw 'Payload placeholder отсутствует.' }
[IO.File]::WriteAllText($output, $template.Replace('__CHAOS_LINK_PAYLOAD__', $base64), $utf8Bom)
[IO.File]::WriteAllText($uninstallOutput, (Get-Content (Join-Path $root 'installer\ChaosLink-Uninstall.ps1') -Raw), $utf8Bom)
Write-Host "Готовый установщик: $output"

$ps2exeModule = Get-Module -ListAvailable ps2exe | Sort-Object Version -Descending | Select-Object -First 1
if ($ps2exeModule) {
    function Build-PowerShellExe($inputFile, $compiledFile, $title, $description) {
        if (Test-Path $compiledFile) { Remove-Item $compiledFile -Force }
        Remove-Item ($compiledFile + '.config') -Force -ErrorAction SilentlyContinue
        $modulePath = $ps2exeModule.Path.Replace("'", "''")
        $inputPath = $inputFile.Replace("'", "''")
        $compiledPath = $compiledFile.Replace("'", "''")
        $safeTitle = $title.Replace("'", "''")
        $safeDescription = $description.Replace("'", "''")
        $compileCommand = @"
Import-Module '$modulePath' -Force
Invoke-ps2exe -inputFile '$inputPath' -outputFile '$compiledPath' -x64 -STA -requireAdmin -supportOS -title '$safeTitle' -description '$safeDescription' -company 'Chaos Link' -product 'Chaos Link' -version '0.5.0.0'
if (-not (Test-Path -LiteralPath '$compiledPath')) { exit 1 }
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($compileCommand))
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $compiledFile)) {
            throw "Не удалось собрать EXE: $compiledFile"
        }
    }

    Build-PowerShellExe $output $exeOutput 'Chaos Link Setup' 'Consent-based Chaos Link gaming PC installer'
    Build-PowerShellExe $uninstallOutput $uninstallExeOutput 'Chaos Link Uninstaller' 'Completely removes the local Chaos Link installation'
    Write-Host "Готовый EXE: $exeOutput"
    Write-Host "Готовый деинсталлятор: $uninstallExeOutput"
} else {
    Write-Warning 'Модуль ps2exe не найден; создан только PowerShell-установщик.'
}

if ($env:CHAOS_LINK_SIGNING_THUMBPRINT) {
    & (Join-Path $root 'scripts\sign-release.ps1') -CertificateThumbprint $env:CHAOS_LINK_SIGNING_THUMBPRINT
} elseif (Test-Path -LiteralPath $exeOutput) {
    Write-Warning 'EXE-файлы не подписаны: переменная CHAOS_LINK_SIGNING_THUMBPRINT не задана.'
}

$checksumFiles = @($output, $uninstallOutput, $exeOutput, $uninstallExeOutput) | Where-Object { Test-Path -LiteralPath $_ }
$checksumLines = $checksumFiles | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($_))"
}
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'), $checksumLines, [Text.UTF8Encoding]::new($false))
Write-Host "Контрольные суммы: $(Join-Path $dist 'SHA256SUMS.txt')"
