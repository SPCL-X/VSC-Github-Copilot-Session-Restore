<#
旧互換ラッパー。内部で restore_copilot_sessions.ps1 に処理を委譲します。
新規に使う場合は restore_copilot_sessions.ps1 を直接使用してください。
#>
param()

Write-Warning 'export_copilot_sessions.ps1 は非推奨です。restore_copilot_sessions.ps1 を使用してください。'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir 'restore_copilot_sessions.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    Write-Error "委譲先のスクリプトが見つかりません: $target"
    exit 1
}

& $target @args
if ($LASTEXITCODE) {
    exit $LASTEXITCODE
}
exit 0
