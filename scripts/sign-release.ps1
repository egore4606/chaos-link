[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Fa-f0-9]{40}$')]
    [string]$CertificateThumbprint,
    [string[]]$Files = @(
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\ChaosLink-Setup.exe'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\ChaosLink-Uninstall.exe')
    ),
    [string]$TimestampUrl = 'http://timestamp.acs.microsoft.com'
)

$ErrorActionPreference = 'Stop'
$kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signTool = Get-ChildItem -LiteralPath $kitsRoot -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $signTool) { throw 'SignTool не найден. Установите Windows SDK.' }

$certificate = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
    Where-Object Thumbprint -eq $CertificateThumbprint |
    Select-Object -First 1
if (-not $certificate) { throw "Сертификат $CertificateThumbprint не найден в хранилище Windows." }
if (-not $certificate.HasPrivateKey) { throw 'У сертификата отсутствует закрытый ключ.' }

foreach ($file in $Files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Файл для подписи не найден: $file" }
    & $signTool.FullName sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $file
    if ($LASTEXITCODE -ne 0) { throw "Не удалось подписать $file" }
    & $signTool.FullName verify /pa /all $file
    if ($LASTEXITCODE -ne 0) { throw "Проверка подписи не прошла: $file" }
}

Write-Host 'Authenticode-подписи созданы и проверены.' -ForegroundColor Green
