<#
旧互換ラッパー。内部で restore_copilot_sessions.ps1 に処理を委譲します。
新規に使う場合は restore_copilot_sessions.ps1 を直接使用してください。
#>
param(
    [ValidateSet('en', 'ja')]
    [string]$Language = 'en'
)

$Messages = @{
    en = @{
        DeprecatedWrapper   = 'export_copilot_sessions.ps1 is deprecated. Use restore_copilot_sessions.ps1 instead.'
        TargetScriptNotFound = 'Delegate script not found: {0}'
    }
    ja = @{
        DeprecatedWrapper   = 'export_copilot_sessions.ps1 は非推奨です。restore_copilot_sessions.ps1 を使用してください。'
        TargetScriptNotFound = '委譲先のスクリプトが見つかりません: {0}'
    }
}

function Get-Text {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Key,
        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [object[]]$FormatArgs
    )
    $lang = if ($Messages.ContainsKey($Language)) { $Language } else { 'en' }
    $template = $Messages[$lang][$Key]
    if (-not $template) { $template = $Key }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) {
        return ($template -f $FormatArgs)
    }
    return $template
}

Write-Warning (Get-Text 'DeprecatedWrapper')

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir 'restore_copilot_sessions.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    Write-Error (Get-Text 'TargetScriptNotFound' $target)
    exit 1
}

& $target @args -Language $Language
if ($LASTEXITCODE) {
    exit $LASTEXITCODE
}
exit 0
