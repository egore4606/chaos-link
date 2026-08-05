[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot '.runtime'
$logs = @(
    (Join-Path $runtimeRoot 'server.out.log'),
    (Join-Path $runtimeRoot 'server.err.log'),
    (Join-Path $runtimeRoot 'agent.out.log'),
    (Join-Path $runtimeRoot 'agent.err.log')
)

$Host.UI.RawUI.WindowTitle = 'Chaos Link — живые логи'
Write-Host 'CHAOS LINK — ЖИВЫЕ ЛОГИ' -ForegroundColor Green
Write-Host 'Подключения друзей, состояние агента и выполненные эффекты появляются здесь.'
Write-Host 'Закрытие этого окна не останавливает Chaos Link.'
Write-Host '------------------------------------------------------------'

foreach ($log in $logs) {
    if (-not (Test-Path -LiteralPath $log)) {
        New-Item -ItemType File -Path $log -Force | Out-Null
    }
}

Get-Content -LiteralPath $logs -Tail 30 -Wait
