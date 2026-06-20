<#
VS Code Copilot Chat セッションの抽出・復元スクリプト。
- 抽出モード: workspaceStorage から chatSessions/*.jsonl を読み、conversation.md / index.md (/ summary.md) を生成する
- 直接復元モード: -RestoreToWorkspaceId 指定時、別の workspaceStorage フォルダ (または restore-package) からセッション関連ファイルをコピーする
#>

[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $env:APPDATA 'Code\User\workspaceStorage'),
    [string]$OutputRoot = '.\CopilotSessionRestore_Output',
    [Nullable[datetime]]$Since,
    [switch]$IncludeSummary,
    [switch]$CreateRestorePackage,
    [string]$RestorePackagePath,
    [string]$RestoreFromWorkspaceId,
    [string]$RestoreToWorkspaceId,
    [string[]]$SessionId,
    [switch]$ForceRestoreOverwrite,
    [switch]$IncludeStateDbIndex,
    [switch]$ListWorkspaces,
    [string]$ListSessionsForWorkspaceId,
    [ValidateSet('en', 'ja')]
    [string]$Language = 'en'
)

$ErrorActionPreference = 'Stop'

# ターミナル出力(Write-Host/Write-Warning/Write-Error/throw)用のメッセージテーブル。
# 生成される Markdown ファイル(conversation.md 等)の内容はここでは対象にしていない。
$Messages = @{
    en = @{
        WorkspaceJsonReadFailed   = 'Failed to read workspace.json ({0}): {1}'
        JsonLineParseFailed       = 'Failed to parse a JSON line ({0}): {1}'
        PatchBeforeSnapshot       = 'A diff line appeared before the kind:0 snapshot ({0}). Skipping this line.'
        StateDbReadFailed         = 'Failed to read state.vscdb: {0}'
        RestoreSkippedExisting    = 'Skipped restoring (already exists): {0} (use -ForceRestoreOverwrite to overwrite)'
        CopyFailed                = 'Failed to copy ({0} -> {1}): {2}'
        SourceNotFound            = 'Source folder not found: {0}'
        SessionReadFailed         = 'Failed to read session ({0}): {1}'
        SessionUnreadable         = 'Could not interpret session content: {0}'
        ExtractSummaryHeader      = '=== Extraction Summary ==='
        ExtractSourceCount        = 'source count (jsonl): {0}'
        ExtractOutputCount        = 'Extracted sessions: {0}'
        OutputLocation            = 'Output: {0}'
        RestoreFromNotFound       = 'Restore source folder not found: {0}'
        RestoreToNotFound         = 'Restore destination folder not found: {0} (open the target workspace in VS Code once first so its workspaceStorage folder is created, then run this again)'
        ChatSessionsNotFound      = 'chatSessions folder not found in restore source: {0}'
        NoSessionsToRestore       = 'No sessions found to restore.'
        StateDbBackedUp           = 'Backed up state.vscdb: {0}'
        StateDbSynced             = 'Synced state.vscdb (history index).'
        StateDbSourceMissing      = "Skipped syncing state.vscdb because the restore source doesn't have one."
        StateDbUntouched          = 'state.vscdb was not touched (-IncludeStateDbIndex not specified).'
        RestoreSummaryHeader      = '=== Direct Restore Summary ==='
        RestoreSourceCount        = 'source session count: {0}'
        RestoreCopiedSkipped      = 'Copied: {0} / Skipped: {1}'
        RestoreDestination        = 'Destination: {0}'
        RestartReminder           = 'IMPORTANT: After restoring, fully quit VS Code and restart it.'
        NoWorkspaceJson           = '(no workspace.json)'
        MultiRootWorkspace        = '(multi-root workspace)'
        FolderMissingMarker       = '⚠ {0} (folder not found - it may have been moved, renamed, or deleted)'
        TotalWorkspaces           = 'Total workspaces: {0}'
        FolderMissingNote         = "Workspaces marked with ⚠ have a recorded folder that can't currently be found. Restoring into one may put data somewhere other than the folder you actually open in VS Code."
        WorkspaceIdHint           = 'Use the WorkspaceId value with -RestoreFromWorkspaceId / -RestoreToWorkspaceId.'
        WorkspaceFolderNotFound   = 'Workspace folder not found: {0}'
        Unreadable                = '(unreadable)'
        NoMessages                = '(no messages)'
        TotalSessions             = 'Total sessions: {0}'
        SessionIdHint             = 'Use the SessionId value with -SessionId to narrow down what gets restored.'
        RestoreFromIdRequired     = 'Direct restore requires -RestoreFromWorkspaceId (when restoring from a restore-package, also specify -RestorePackagePath and set -RestoreFromWorkspaceId to "restore-package").'
        ProcessingError           = 'An error occurred while processing: {0}'
    }
    ja = @{
        WorkspaceJsonReadFailed   = 'workspace.json の読み取りに失敗しました ({0}): {1}'
        JsonLineParseFailed       = 'JSON行の解析に失敗しました ({0}): {1}'
        PatchBeforeSnapshot       = 'スナップショット(kind:0)が見つかる前に差分行が出現しました ({0})。この行は無視します。'
        StateDbReadFailed         = 'state.vscdb の読み取りに失敗しました: {0}'
        RestoreSkippedExisting    = '既存のため復元をスキップしました: {0} (上書きするには -ForceRestoreOverwrite を指定してください)'
        CopyFailed                = 'コピーに失敗しました ({0} -> {1}): {2}'
        SourceNotFound            = '抽出元フォルダが見つかりません: {0}'
        SessionReadFailed         = 'セッション読み取りに失敗しました ({0}): {1}'
        SessionUnreadable         = 'セッション内容を解釈できませんでした: {0}'
        ExtractSummaryHeader      = '=== 抽出結果サマリー ==='
        ExtractSourceCount        = 'source 件数 (jsonl): {0}'
        ExtractOutputCount        = '出力済みセッション件数: {0}'
        OutputLocation            = '出力先: {0}'
        RestoreFromNotFound       = '復元元フォルダが見つかりません: {0}'
        RestoreToNotFound         = '復元先フォルダが見つかりません: {0} （対象ワークスペースを一度VS Codeで開いてworkspaceStorageフォルダを生成してから実行してください）'
        ChatSessionsNotFound      = '復元元に chatSessions フォルダが見つかりません: {0}'
        NoSessionsToRestore       = '復元対象のセッションが見つかりませんでした。'
        StateDbBackedUp           = 'state.vscdb をバックアップしました: {0}'
        StateDbSynced             = 'state.vscdb を同期しました（履歴表示用インデックス）。'
        StateDbSourceMissing      = '復元元に state.vscdb が見つからないため同期をスキップしました。'
        StateDbUntouched          = 'state.vscdb には触れていません（-IncludeStateDbIndex 未指定）。'
        RestoreSummaryHeader      = '=== 直接復元結果サマリー ==='
        RestoreSourceCount        = 'source セッション件数: {0}'
        RestoreCopiedSkipped      = 'コピー件数: {0} / スキップ件数: {1}'
        RestoreDestination        = '復元先: {0}'
        RestartReminder           = '重要: 復元後はVS Codeを完全終了し、再起動してください。'
        NoWorkspaceJson           = '(workspace.json なし)'
        MultiRootWorkspace        = '(マルチルートワークスペース)'
        FolderMissingMarker       = '⚠ {0} (フォルダが見つかりません。移動/改名/削除済みの可能性)'
        TotalWorkspaces           = '合計ワークスペース数: {0}'
        FolderMissingNote         = '⚠ が付いているワークスペースは、記録されたフォルダが現在見つかりません。復元先として指定すると、実際にVS Codeで開いているフォルダとは異なる場所に復元してしまう可能性があるため注意してください。'
        WorkspaceIdHint           = 'WorkspaceId の値を -RestoreFromWorkspaceId / -RestoreToWorkspaceId に指定してください。'
        WorkspaceFolderNotFound   = 'ワークスペースフォルダが見つかりません: {0}'
        Unreadable                = '(読み取り不可)'
        NoMessages                = '(発言なし)'
        TotalSessions             = '合計セッション数: {0}'
        SessionIdHint             = 'SessionId の値を -SessionId に指定すると、直接復元の対象を絞り込めます。'
        RestoreFromIdRequired     = '直接復元には RestoreFromWorkspaceId を指定してください（restore-package から復元する場合は RestorePackagePath も併せて指定し、RestoreFromWorkspaceId には "restore-package" を指定します）。'
        ProcessingError           = '処理中にエラーが発生しました: {0}'
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

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertFrom-FileUri {
    param([string]$Uri)
    if (-not $Uri) { return $null }
    try {
        $u = [Uri]$Uri
        # VS Code は file:// URI のコロンを %3A としてエスケープするため、
        # System.Uri の Windows ドライブ文字認識(LocalPath)が効かない。手動でデコードする。
        $path = [Uri]::UnescapeDataString($u.AbsolutePath)
        if ($path -match '^/[A-Za-z]:') { $path = $path.Substring(1) }
        return $path.Replace('/', '\')
    } catch {
        return $null
    }
}

function Get-WorkspaceFolderPath {
    # 戻り値が "(" で始まる文字列は実フォルダパスではない(マルチルート等)ことを示す目印。
    # 呼び出し側はこの規約で存在チェック対象かどうかを判定する。
    param($WorkspaceDir)
    $wsJsonPath = Join-Path $WorkspaceDir.FullName 'workspace.json'
    if (-not (Test-Path -LiteralPath $wsJsonPath)) { return $null }
    try {
        $wsJson = Get-Content -LiteralPath $wsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($wsJson.folder) {
            return ConvertFrom-FileUri -Uri $wsJson.folder
        }
        if ($wsJson.workspace) {
            return (Get-Text 'MultiRootWorkspace')
        }
    } catch {
        Write-Warning (Get-Text 'WorkspaceJsonReadFailed' $wsJsonPath $_.Exception.Message)
    }
    return $null
}

function Test-WorkspaceFolderPath {
    param([string]$FolderPath)
    if (-not $FolderPath) { return $true }
    if ($FolderPath.StartsWith('(')) { return $true }
    return (Test-Path -LiteralPath $FolderPath)
}

function Get-WorkspaceLabel {
    param($WorkspaceDir)
    $decoded = Get-WorkspaceFolderPath -WorkspaceDir $WorkspaceDir
    if ($decoded) {
        $sanitized = ($decoded -replace '[:\\/\s<>"|?*]+', '-').Trim('-')
        $shortId = $WorkspaceDir.Name.Substring(0, [Math]::Min(8, $WorkspaceDir.Name.Length))
        return "${sanitized}__$shortId"
    }
    return $WorkspaceDir.Name
}

function Set-JsonPatchValue {
    # chatSessions/*.jsonl の kind:1/2 行は「パスkに値vを設定する」という差分更新であり、
    # 配列はパス末尾に到達するまで毎回丸ごと置き換えられるため、範囲外インデックスへの
    # 追記は基本的に発生しない想定だが、念のため配列拡張にも対応しておく。
    param($Container, [object[]]$Path, $Value)

    $key = $Path[0]
    $rest = if ($Path.Count -gt 1) { $Path[1..($Path.Count - 1)] } else { @() }
    $isIndex = ($key -is [int]) -or ($key -is [long]) -or ($key -is [double])

    if ($isIndex) {
        $idx = [int]$key
        $arr = @($Container)
        if ($idx -ge $arr.Count) {
            $newArr = New-Object object[] ($idx + 1)
            for ($i = 0; $i -lt $arr.Count; $i++) { $newArr[$i] = $arr[$i] }
            $arr = $newArr
        }
        if ($rest.Count -eq 0) {
            $arr[$idx] = $Value
        } else {
            $arr[$idx] = Set-JsonPatchValue -Container $arr[$idx] -Path $rest -Value $Value
        }
        return , $arr
    } else {
        if ($null -eq $Container -or -not ($Container -is [System.Management.Automation.PSCustomObject])) {
            $obj = New-Object PSCustomObject
        } else {
            $obj = $Container
        }
        $hasProp = $obj.PSObject.Properties.Match($key).Count -gt 0
        if ($rest.Count -eq 0) {
            $newValue = $Value
        } else {
            $existingChild = if ($hasProp) { $obj.$key } else { $null }
            $newValue = Set-JsonPatchValue -Container $existingChild -Path $rest -Value $Value
        }
        if ($hasProp) {
            $obj.$key = $newValue
        } else {
            Add-Member -InputObject $obj -NotePropertyName $key -NotePropertyValue $newValue -Force
        }
        return $obj
    }
}

function Read-ChatSessionFile {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    $sessionObj = $null
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning (Get-Text 'JsonLineParseFailed' $Path $_.Exception.Message)
            continue
        }
        if ($record.kind -eq 0) {
            # kind:0 は完全なスナップショット。これを基点に以降の差分(kind:1/2)を適用していく。
            $sessionObj = $record.v
        } elseif ($null -ne $record.k) {
            if ($null -eq $sessionObj) {
                Write-Warning (Get-Text 'PatchBeforeSnapshot' $Path)
                continue
            }
            $sessionObj = Set-JsonPatchValue -Container $sessionObj -Path @($record.k) -Value $record.v
        }
    }
    return $sessionObj
}

function Get-MessageText {
    param($Message)
    if ($null -eq $Message) { return '' }
    if ($Message -is [string]) { return $Message }
    if ($Message.PSObject.Properties.Match('text').Count -gt 0 -and $Message.text) {
        return [string]$Message.text
    }
    if ($Message.PSObject.Properties.Match('parts').Count -gt 0 -and $Message.parts) {
        $texts = foreach ($p in @($Message.parts)) {
            if ($p.text) { $p.text } elseif ($p.value) { Get-MessageText $p.value } else { $null }
        }
        return (($texts | Where-Object { $_ }) -join "`n")
    }
    return ($Message | ConvertTo-Json -Depth 10 -Compress)
}

function Get-ResponsePartText {
    param($Part)
    if ($null -eq $Part) { return $null }
    if ($Part -is [string]) { return $Part }

    $kind = $null
    if ($Part.PSObject.Properties.Match('kind').Count -gt 0) { $kind = $Part.kind }

    switch ($kind) {
        'mcpServersStarting' {
            # 内部的なノイズで会話内容を持たないため除外する
            return $null
        }
        'inlineReference' {
            $ref = $Part.inlineReference
            $refPath = $null
            if ($ref) {
                if ($ref.PSObject.Properties.Match('fsPath').Count -gt 0) { $refPath = $ref.fsPath }
                elseif ($ref.PSObject.Properties.Match('path').Count -gt 0) { $refPath = $ref.path }
            }
            if ($refPath) { return "``$refPath``" }
            return $null
        }
        'toolInvocationSerialized' {
            $im = $Part.invocationMessage
            $msg = $null
            if ($im -is [string]) { $msg = $im }
            elseif ($im -and $im.PSObject.Properties.Match('value').Count -gt 0) { $msg = [string]$im.value }
            if ([string]::IsNullOrWhiteSpace($msg)) { return $null }
            return "_($msg)_"
        }
        'thinking' {
            $v = $Part.value
            if ($v -is [string] -and -not [string]::IsNullOrWhiteSpace($v)) {
                return (($v -split "`n" | ForEach-Object { "> $_" }) -join "`n")
            }
            return $null
        }
    }

    if ($Part.PSObject.Properties.Match('value').Count -gt 0) {
        $v = $Part.value
        if ($v -is [string]) { return $v }
        if ($v -and $v.PSObject.Properties.Match('value').Count -gt 0) { return [string]$v.value }
    }
    if ($Part.PSObject.Properties.Match('text').Count -gt 0 -and $Part.text) {
        return [string]$Part.text
    }
    # 未知の形式は情報を失わないように JSON のまま出力する
    $json = $Part | ConvertTo-Json -Depth 10 -Compress
    return "``````json`n$json`n``````"
}

function Get-ResponseText {
    param($Response)
    if ($null -eq $Response) { return '' }
    if ($Response -is [string]) { return $Response }
    $parts = @()
    foreach ($part in @($Response)) {
        $parts += (Get-ResponsePartText $part)
    }
    return (($parts | Where-Object { $_ }) -join "`n")
}

function ConvertTo-ConversationMarkdown {
    param($Session, [string]$SessionId)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## Session $SessionId")
    if ($Session.creationDate) {
        try {
            $created = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Session.creationDate).LocalDateTime
            [void]$sb.AppendLine("- 作成日時: $created")
        } catch {}
    }
    $requests = @($Session.requests)
    [void]$sb.AppendLine("- 発言数: $($requests.Count)")
    [void]$sb.AppendLine('')
    $i = 0
    foreach ($req in $requests) {
        $i++
        [void]$sb.AppendLine("### Turn $i")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**User:**')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((Get-MessageText $req.message))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**Copilot:**')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((Get-ResponseText $req.response))
        [void]$sb.AppendLine('')
    }
    return $sb.ToString()
}

function Build-SessionSummaryHeuristic {
    param($Session, [string]$SessionId)
    $requests = @($Session.requests)
    $topic = ''
    if ($requests.Count -gt 0) {
        $topic = (Get-MessageText $requests[0].message).Trim()
    }
    if ($topic.Length -gt 120) { $topic = $topic.Substring(0, 120) + '…' }
    if ([string]::IsNullOrWhiteSpace($topic)) { $topic = '(発言なし)' } # summary.md はファイル内容のため言語切替の対象外
    [PSCustomObject]@{
        SessionId    = $SessionId
        Topic        = $topic
        MessageCount = $requests.Count
    }
}

function Test-StateDbContainsId {
    param([string]$StateDbPath, [string]$Id)
    if (-not (Test-Path -LiteralPath $StateDbPath)) { return $false }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($StateDbPath)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        return $text.Contains($Id)
    } catch {
        Write-Warning (Get-Text 'StateDbReadFailed' $_.Exception.Message)
        return $false
    }
}

function Build-IndexMarkdown {
    param($Rows, [switch]$IncludeHistoryColumn, [string]$WorkspaceFolder, [string]$FolderLabel)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Index: $FolderLabel")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("元ワークスペースID: $WorkspaceFolder")
    [void]$sb.AppendLine('')
    if ($IncludeHistoryColumn) {
        [void]$sb.AppendLine('| SessionId | 作成日時 | 発言数 | UI履歴に残存 |')
        [void]$sb.AppendLine('|---|---|---|---|')
    } else {
        [void]$sb.AppendLine('| SessionId | 作成日時 | 発言数 |')
        [void]$sb.AppendLine('|---|---|---|')
    }
    foreach ($r in $Rows) {
        if ($IncludeHistoryColumn) {
            $hist = if ($r.InHistory) { 'Yes' } else { 'No' }
            [void]$sb.AppendLine("| $($r.SessionId) | $($r.Created) | $($r.MessageCount) | $hist |")
        } else {
            [void]$sb.AppendLine("| $($r.SessionId) | $($r.Created) | $($r.MessageCount) |")
        }
    }
    return $sb.ToString()
}

function Build-SummaryMarkdown {
    param($Rows)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Summary (heuristic)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('この要約はAIを使わず、各セッションの最初のユーザー発言の冒頭を機械的に抜粋したものです。')
    [void]$sb.AppendLine('')
    foreach ($r in $Rows) {
        [void]$sb.AppendLine("## $($r.SessionId)")
        [void]$sb.AppendLine("- 発言数: $($r.MessageCount)")
        [void]$sb.AppendLine("- 話題（冒頭抜粋）: $($r.Topic)")
        [void]$sb.AppendLine('')
    }
    return $sb.ToString()
}

function Get-ArtifactSpecs {
    param([string]$SessionId)
    return @(
        @{ Type = 'File'; Rel = "chatSessions\$SessionId.jsonl" },
        @{ Type = 'Dir';  Rel = "chatEditingSessions\$SessionId" },
        @{ Type = 'File'; Rel = "GitHub.copilot-chat\transcripts\$SessionId.jsonl" },
        @{ Type = 'Dir';  Rel = "GitHub.copilot-chat\debug-logs\$SessionId" }
    )
}

function Copy-ArtifactSet {
    param(
        [string]$SourceWorkspaceDir,
        [string]$DestWorkspaceDir,
        [string]$SessionId,
        [switch]$Force
    )
    $copied = @()
    $skipped = @()

    foreach ($a in (Get-ArtifactSpecs -SessionId $SessionId)) {
        $srcPath = Join-Path $SourceWorkspaceDir $a.Rel
        if (-not (Test-Path -LiteralPath $srcPath)) { continue }

        $destPath = Join-Path $DestWorkspaceDir $a.Rel
        $destParent = Split-Path $destPath -Parent
        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        $exists = Test-Path -LiteralPath $destPath
        if ($exists -and -not $Force) {
            Write-Warning (Get-Text 'RestoreSkippedExisting' $destPath)
            $skipped += $a.Rel
            continue
        }

        try {
            if ($a.Type -eq 'Dir') {
                Copy-Item -LiteralPath $srcPath -Destination $destPath -Recurse -Force
            } else {
                Copy-Item -LiteralPath $srcPath -Destination $destPath -Force
            }
            $copied += $a.Rel
        } catch {
            Write-Warning (Get-Text 'CopyFailed' $srcPath $destPath $_.Exception.Message)
        }
    }

    [PSCustomObject]@{ SessionId = $SessionId; Copied = $copied; Skipped = $skipped }
}

function Build-RestoreReadme {
    param([string]$WorkspaceId, [string[]]$SessionIds, [string]$PackageParentHint)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# restore-package の使い方')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("元ワークスペースID: $WorkspaceId")
    [void]$sb.AppendLine("含まれるセッション数: $($SessionIds.Count)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('別のPC・別のユーザー環境にこのフォルダ（restore-package）ごとコピーした上で、')
    [void]$sb.AppendLine('次のように実行すると復元先の workspaceStorage フォルダへ直接復元できます。')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('```powershell')
    [void]$sb.AppendLine(".\restore_copilot_sessions.ps1 ``")
    [void]$sb.AppendLine("    -RestorePackagePath `"$PackageParentHint`" ``")
    [void]$sb.AppendLine('    -RestoreFromWorkspaceId "restore-package" `')
    [void]$sb.AppendLine('    -RestoreToWorkspaceId "<復元先のworkspaceStorageフォルダ名>" `')
    [void]$sb.AppendLine('    -ForceRestoreOverwrite')
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('注意:')
    [void]$sb.AppendLine('- 復元先は事前にVS Codeで一度開き、workspaceStorageフォルダが生成されている必要があります。')
    [void]$sb.AppendLine('- 別PC・別ユーザー環境への移植時は文脈（ファイルパスや環境）が異なる可能性があるため、必要であれば新規セッションを開始してください。')
    [void]$sb.AppendLine('- -IncludeStateDbIndex は履歴表示用の補助機能であり、常用は避けてください。')
    [void]$sb.AppendLine('- 復元後はVS Codeを完全終了し、再起動してください。')
    return $sb.ToString()
}

function New-RestorePackage {
    param($WorkspaceDir, [string]$OutDir, [string[]]$SessionIds)
    $pkgDir = Join-Path $OutDir 'restore-package'
    New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null

    foreach ($sid in $SessionIds) {
        Copy-ArtifactSet -SourceWorkspaceDir $WorkspaceDir.FullName -DestWorkspaceDir $pkgDir -SessionId $sid -Force:$true | Out-Null
    }

    $wsJson = Join-Path $WorkspaceDir.FullName 'workspace.json'
    if (Test-Path -LiteralPath $wsJson) {
        Copy-Item -LiteralPath $wsJson -Destination $pkgDir -Force
    }

    $readme = Build-RestoreReadme -WorkspaceId $WorkspaceDir.Name -SessionIds $SessionIds -PackageParentHint $OutDir
    Write-Utf8NoBom -Path (Join-Path $pkgDir 'README_restore.md') -Content $readme
}

function Invoke-ExtractMode {
    param(
        [string]$SourceRoot,
        [string]$OutputRoot,
        [Nullable[datetime]]$Since,
        [switch]$IncludeSummary,
        [switch]$CreateRestorePackage,
        [switch]$IncludeStateDbIndex
    )

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw (Get-Text 'SourceNotFound' $SourceRoot)
    }
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

    $workspaceDirs = Get-ChildItem -LiteralPath $SourceRoot -Directory -ErrorAction SilentlyContinue
    $totalSource = 0
    $totalOutput = 0

    foreach ($wsDir in $workspaceDirs) {
        $chatSessionsPath = Join-Path $wsDir.FullName 'chatSessions'
        if (-not (Test-Path -LiteralPath $chatSessionsPath)) { continue }

        $jsonlFiles = Get-ChildItem -LiteralPath $chatSessionsPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue
        if (-not $jsonlFiles) { continue }
        if ($null -ne $Since) {
            $jsonlFiles = @($jsonlFiles | Where-Object { $_.LastWriteTime -ge $Since })
        }
        if (-not $jsonlFiles -or $jsonlFiles.Count -eq 0) { continue }

        $totalSource += $jsonlFiles.Count

        $folderLabel = Get-WorkspaceLabel -WorkspaceDir $wsDir
        $outDir = Join-Path $OutputRoot $folderLabel
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null

        $conversationParts = @()
        $indexRows = @()
        $summaryRows = @()

        foreach ($jf in $jsonlFiles) {
            $sessionId = $jf.BaseName
            try {
                $session = Read-ChatSessionFile -Path $jf.FullName
            } catch {
                Write-Warning (Get-Text 'SessionReadFailed' $jf.FullName $_.Exception.Message)
                continue
            }
            if ($null -eq $session) {
                Write-Warning (Get-Text 'SessionUnreadable' $jf.FullName)
                continue
            }

            $conversationParts += (ConvertTo-ConversationMarkdown -Session $session -SessionId $sessionId)

            $reqCount = @($session.requests).Count
            $createdStr = ''
            if ($session.creationDate) {
                try {
                    $createdStr = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$session.creationDate).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
                } catch {}
            }

            $inHistory = $false
            if ($IncludeStateDbIndex) {
                $inHistory = Test-StateDbContainsId -StateDbPath (Join-Path $wsDir.FullName 'state.vscdb') -Id $sessionId
            }

            $indexRows += [PSCustomObject]@{
                SessionId    = $sessionId
                Created      = $createdStr
                MessageCount = $reqCount
                InHistory    = $inHistory
            }

            if ($IncludeSummary) {
                $summaryRows += (Build-SessionSummaryHeuristic -Session $session -SessionId $sessionId)
            }

            $totalOutput++
        }

        Write-Utf8NoBom -Path (Join-Path $outDir 'conversation.md') -Content (($conversationParts -join "`n---`n`n"))

        $indexMd = Build-IndexMarkdown -Rows $indexRows -IncludeHistoryColumn:$IncludeStateDbIndex -WorkspaceFolder $wsDir.Name -FolderLabel $folderLabel
        Write-Utf8NoBom -Path (Join-Path $outDir 'index.md') -Content $indexMd

        if ($IncludeSummary) {
            $summaryMd = Build-SummaryMarkdown -Rows $summaryRows
            Write-Utf8NoBom -Path (Join-Path $outDir 'summary.md') -Content $summaryMd
        }

        if ($CreateRestorePackage) {
            New-RestorePackage -WorkspaceDir $wsDir -OutDir $outDir -SessionIds @($jsonlFiles | ForEach-Object { $_.BaseName })
        }
    }

    Write-Host ''
    Write-Host (Get-Text 'ExtractSummaryHeader')
    Write-Host (Get-Text 'ExtractSourceCount' $totalSource)
    Write-Host (Get-Text 'ExtractOutputCount' $totalOutput)
    Write-Host (Get-Text 'OutputLocation' $OutputRoot)
}

function Invoke-DirectRestoreMode {
    param(
        [string]$SourceRoot,
        [string]$RestorePackagePath,
        [string]$RestoreFromWorkspaceId,
        [string]$RestoreToWorkspaceId,
        [string[]]$SessionId,
        [switch]$ForceRestoreOverwrite,
        [switch]$IncludeStateDbIndex
    )

    if ($RestorePackagePath) {
        $fromRoot = Join-Path $RestorePackagePath $RestoreFromWorkspaceId
    } else {
        $fromRoot = Join-Path $SourceRoot $RestoreFromWorkspaceId
    }
    $toRoot = Join-Path $SourceRoot $RestoreToWorkspaceId

    if (-not (Test-Path -LiteralPath $fromRoot)) {
        throw (Get-Text 'RestoreFromNotFound' $fromRoot)
    }
    if (-not (Test-Path -LiteralPath $toRoot)) {
        throw (Get-Text 'RestoreToNotFound' $toRoot)
    }

    $chatSessionsPath = Join-Path $fromRoot 'chatSessions'
    if (-not (Test-Path -LiteralPath $chatSessionsPath)) {
        throw (Get-Text 'ChatSessionsNotFound' $chatSessionsPath)
    }

    $sessionFiles = @(Get-ChildItem -LiteralPath $chatSessionsPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
    if ($SessionId -and $SessionId.Count -gt 0) {
        $sessionFiles = @($sessionFiles | Where-Object { $SessionId -contains $_.BaseName })
    }

    if ($sessionFiles.Count -eq 0) {
        Write-Warning (Get-Text 'NoSessionsToRestore')
        return
    }

    $copiedCount = 0
    $skippedCount = 0
    foreach ($sf in $sessionFiles) {
        $result = Copy-ArtifactSet -SourceWorkspaceDir $fromRoot -DestWorkspaceDir $toRoot -SessionId $sf.BaseName -Force:$ForceRestoreOverwrite
        $copiedCount += $result.Copied.Count
        $skippedCount += $result.Skipped.Count
    }

    if ($IncludeStateDbIndex) {
        $fromDb = Join-Path $fromRoot 'state.vscdb'
        $toDb = Join-Path $toRoot 'state.vscdb'
        if (Test-Path -LiteralPath $fromDb) {
            if (Test-Path -LiteralPath $toDb) {
                $backupPath = "$toDb.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -LiteralPath $toDb -Destination $backupPath -Force
                Write-Host (Get-Text 'StateDbBackedUp' $backupPath)
            }
            Copy-Item -LiteralPath $fromDb -Destination $toDb -Force
            Write-Host (Get-Text 'StateDbSynced')
        } else {
            Write-Warning (Get-Text 'StateDbSourceMissing')
        }
    } else {
        Write-Host (Get-Text 'StateDbUntouched')
    }

    Write-Host ''
    Write-Host (Get-Text 'RestoreSummaryHeader')
    Write-Host (Get-Text 'RestoreSourceCount' $sessionFiles.Count)
    Write-Host (Get-Text 'RestoreCopiedSkipped' $copiedCount $skippedCount)
    Write-Host (Get-Text 'RestoreDestination' $toRoot)
    Write-Host ''
    Write-Host (Get-Text 'RestartReminder')
}

function Invoke-ListWorkspaces {
    param([string]$SourceRoot)

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw (Get-Text 'SourceNotFound' $SourceRoot)
    }

    $rows = @()
    foreach ($wsDir in (Get-ChildItem -LiteralPath $SourceRoot -Directory -ErrorAction SilentlyContinue)) {
        $chatSessionsPath = Join-Path $wsDir.FullName 'chatSessions'
        $sessionFiles = @()
        if (Test-Path -LiteralPath $chatSessionsPath) {
            $sessionFiles = @(Get-ChildItem -LiteralPath $chatSessionsPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
        }
        $lastModified = $null
        if ($sessionFiles.Count -gt 0) {
            $lastModified = ($sessionFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        }
        $folderPath = Get-WorkspaceFolderPath -WorkspaceDir $wsDir
        if (-not $folderPath) {
            $folderPath = Get-Text 'NoWorkspaceJson'
        } elseif (-not (Test-WorkspaceFolderPath -FolderPath $folderPath)) {
            $folderPath = Get-Text 'FolderMissingMarker' $folderPath
        }

        $rows += [PSCustomObject]@{
            WorkspaceId   = $wsDir.Name
            Folder        = $folderPath
            SessionCount  = $sessionFiles.Count
            LastSessionAt = $lastModified
        }
    }

    $rows = @($rows | Sort-Object -Property @{ Expression = 'LastSessionAt'; Descending = $true })
    $rows | Format-Table -AutoSize -Property WorkspaceId, Folder, SessionCount, LastSessionAt | Out-String -Width 4096 | Write-Host
    Write-Host (Get-Text 'TotalWorkspaces' $rows.Count)
    Write-Host (Get-Text 'FolderMissingNote')
    Write-Host ''
    Write-Host (Get-Text 'WorkspaceIdHint')
}

function Invoke-ListSessions {
    param([string]$SourceRoot, [string]$WorkspaceId)

    $wsPath = Join-Path $SourceRoot $WorkspaceId
    if (-not (Test-Path -LiteralPath $wsPath)) {
        throw (Get-Text 'WorkspaceFolderNotFound' $wsPath)
    }
    $chatSessionsPath = Join-Path $wsPath 'chatSessions'
    if (-not (Test-Path -LiteralPath $chatSessionsPath)) {
        throw (Get-Text 'ChatSessionsNotFound' $chatSessionsPath)
    }

    $rows = @()
    foreach ($jf in (Get-ChildItem -LiteralPath $chatSessionsPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
        $topic = Get-Text 'Unreadable'
        $reqCount = 0
        try {
            $session = Read-ChatSessionFile -Path $jf.FullName
            if ($session) {
                $reqCount = @($session.requests).Count
                if ($reqCount -gt 0) {
                    $topic = (Get-MessageText $session.requests[0].message).Trim()
                    if ($topic.Length -gt 60) { $topic = $topic.Substring(0, 60) + '…' }
                } else {
                    $topic = Get-Text 'NoMessages'
                }
            }
        } catch {
            Write-Warning (Get-Text 'SessionReadFailed' $jf.FullName $_.Exception.Message)
        }

        $rows += [PSCustomObject]@{
            SessionId    = $jf.BaseName
            LastModified = $jf.LastWriteTime
            MessageCount = $reqCount
            Topic        = $topic
        }
    }

    $rows = @($rows | Sort-Object LastModified -Descending)
    $rows | Format-Table -AutoSize -Property SessionId, LastModified, MessageCount, Topic | Out-String -Width 4096 | Write-Host
    Write-Host (Get-Text 'TotalSessions' $rows.Count)
    Write-Host ''
    Write-Host (Get-Text 'SessionIdHint')
}

try {
    if ($ListWorkspaces) {
        Invoke-ListWorkspaces -SourceRoot $SourceRoot
    } elseif ($ListSessionsForWorkspaceId) {
        Invoke-ListSessions -SourceRoot $SourceRoot -WorkspaceId $ListSessionsForWorkspaceId
    } elseif ($RestoreToWorkspaceId) {
        if (-not $RestoreFromWorkspaceId -and -not $RestorePackagePath) {
            throw (Get-Text 'RestoreFromIdRequired')
        }
        # RestorePackagePath 指定時に RestoreFromWorkspaceId を省略した場合は "restore-package" を既定値として使う
        $effectiveFromId = if ($RestoreFromWorkspaceId) { $RestoreFromWorkspaceId } else { 'restore-package' }
        Invoke-DirectRestoreMode -SourceRoot $SourceRoot -RestorePackagePath $RestorePackagePath -RestoreFromWorkspaceId $effectiveFromId -RestoreToWorkspaceId $RestoreToWorkspaceId -SessionId $SessionId -ForceRestoreOverwrite:$ForceRestoreOverwrite -IncludeStateDbIndex:$IncludeStateDbIndex
    } else {
        Invoke-ExtractMode -SourceRoot $SourceRoot -OutputRoot $OutputRoot -Since $Since -IncludeSummary:$IncludeSummary -CreateRestorePackage:$CreateRestorePackage -IncludeStateDbIndex:$IncludeStateDbIndex
    }
} catch {
    Write-Error (Get-Text 'ProcessingError' $_.Exception.Message)
    exit 1
}
