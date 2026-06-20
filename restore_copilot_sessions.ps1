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
    [string]$ListSessionsForWorkspaceId
)

$ErrorActionPreference = 'Stop'

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
    param($WorkspaceDir)
    $wsJsonPath = Join-Path $WorkspaceDir.FullName 'workspace.json'
    if (-not (Test-Path -LiteralPath $wsJsonPath)) { return $null }
    try {
        $wsJson = Get-Content -LiteralPath $wsJsonPath -Raw | ConvertFrom-Json
        if ($wsJson.folder) {
            return ConvertFrom-FileUri -Uri $wsJson.folder
        }
    } catch {
        Write-Warning "workspace.json の読み取りに失敗しました ($wsJsonPath): $($_.Exception.Message)"
    }
    return $null
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

function Read-ChatSessionFile {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    $sessionObj = $null
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "JSON行の解析に失敗しました ($Path): $($_.Exception.Message)"
            continue
        }
        if ($null -ne $record.v) {
            $sessionObj = $record.v
        } elseif ($null -eq $sessionObj) {
            $sessionObj = $record
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
    if ([string]::IsNullOrWhiteSpace($topic)) { $topic = '(発言なし)' }
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
        Write-Warning "state.vscdb の読み取りに失敗しました: $($_.Exception.Message)"
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
            Write-Warning "既存のため復元をスキップしました: $destPath (上書きするには -ForceRestoreOverwrite を指定してください)"
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
            Write-Warning "コピーに失敗しました ($srcPath -> $destPath): $($_.Exception.Message)"
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
        throw "抽出元フォルダが見つかりません: $SourceRoot"
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
                Write-Warning "セッション読み取りに失敗しました ($($jf.FullName)): $($_.Exception.Message)"
                continue
            }
            if ($null -eq $session) {
                Write-Warning "セッション内容を解釈できませんでした: $($jf.FullName)"
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
    Write-Host '=== 抽出結果サマリー ==='
    Write-Host "source 件数 (jsonl): $totalSource"
    Write-Host "出力済みセッション件数: $totalOutput"
    Write-Host "出力先: $OutputRoot"
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
        throw "復元元フォルダが見つかりません: $fromRoot"
    }
    if (-not (Test-Path -LiteralPath $toRoot)) {
        throw "復元先フォルダが見つかりません: $toRoot （対象ワークスペースを一度VS Codeで開いてworkspaceStorageフォルダを生成してから実行してください）"
    }

    $chatSessionsPath = Join-Path $fromRoot 'chatSessions'
    if (-not (Test-Path -LiteralPath $chatSessionsPath)) {
        throw "復元元に chatSessions フォルダが見つかりません: $chatSessionsPath"
    }

    $sessionFiles = @(Get-ChildItem -LiteralPath $chatSessionsPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
    if ($SessionId -and $SessionId.Count -gt 0) {
        $sessionFiles = @($sessionFiles | Where-Object { $SessionId -contains $_.BaseName })
    }

    if ($sessionFiles.Count -eq 0) {
        Write-Warning '復元対象のセッションが見つかりませんでした。'
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
                Write-Host "state.vscdb をバックアップしました: $backupPath"
            }
            Copy-Item -LiteralPath $fromDb -Destination $toDb -Force
            Write-Host 'state.vscdb を同期しました（履歴表示用インデックス）。'
        } else {
            Write-Warning '復元元に state.vscdb が見つからないため同期をスキップしました。'
        }
    } else {
        Write-Host 'state.vscdb には触れていません（-IncludeStateDbIndex 未指定）。'
    }

    Write-Host ''
    Write-Host '=== 直接復元結果サマリー ==='
    Write-Host "source セッション件数: $($sessionFiles.Count)"
    Write-Host "コピー件数: $copiedCount / スキップ件数: $skippedCount"
    Write-Host "復元先: $toRoot"
    Write-Host ''
    Write-Host '重要: 復元後はVS Codeを完全終了し、再起動してください。'
}

function Invoke-ListWorkspaces {
    param([string]$SourceRoot)

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw "抽出元フォルダが見つかりません: $SourceRoot"
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
        if (-not $folderPath) { $folderPath = '(workspace.json なし)' }

        $rows += [PSCustomObject]@{
            WorkspaceId   = $wsDir.Name
            Folder        = $folderPath
            SessionCount  = $sessionFiles.Count
            LastSessionAt = $lastModified
        }
    }

    $rows = @($rows | Sort-Object -Property @{ Expression = 'LastSessionAt'; Descending = $true })
    $rows | Format-Table -AutoSize -Property WorkspaceId, Folder, SessionCount, LastSessionAt | Out-String -Width 4096 | Write-Host
    Write-Host "合計ワークスペース数: $($rows.Count)"
    Write-Host ''
    Write-Host 'WorkspaceId の値を -RestoreFromWorkspaceId / -RestoreToWorkspaceId に指定してください。'
}

function Invoke-ListSessions {
    param([string]$SourceRoot, [string]$WorkspaceId)

    $wsPath = Join-Path $SourceRoot $WorkspaceId
    if (-not (Test-Path -LiteralPath $wsPath)) {
        throw "ワークスペースフォルダが見つかりません: $wsPath"
    }
    $chatSessionsPath = Join-Path $wsPath 'chatSessions'
    if (-not (Test-Path -LiteralPath $chatSessionsPath)) {
        throw "chatSessions フォルダが見つかりません: $chatSessionsPath"
    }

    $rows = @()
    foreach ($jf in (Get-ChildItem -LiteralPath $chatSessionsPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
        $topic = '(読み取り不可)'
        $reqCount = 0
        try {
            $session = Read-ChatSessionFile -Path $jf.FullName
            if ($session) {
                $reqCount = @($session.requests).Count
                if ($reqCount -gt 0) {
                    $topic = (Get-MessageText $session.requests[0].message).Trim()
                    if ($topic.Length -gt 60) { $topic = $topic.Substring(0, 60) + '…' }
                } else {
                    $topic = '(発言なし)'
                }
            }
        } catch {
            Write-Warning "セッション読み取りに失敗しました ($($jf.FullName)): $($_.Exception.Message)"
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
    Write-Host "合計セッション数: $($rows.Count)"
    Write-Host ''
    Write-Host 'SessionId の値を -SessionId に指定すると、直接復元の対象を絞り込めます。'
}

try {
    if ($ListWorkspaces) {
        Invoke-ListWorkspaces -SourceRoot $SourceRoot
    } elseif ($ListSessionsForWorkspaceId) {
        Invoke-ListSessions -SourceRoot $SourceRoot -WorkspaceId $ListSessionsForWorkspaceId
    } elseif ($RestoreToWorkspaceId) {
        if (-not $RestoreFromWorkspaceId -and -not $RestorePackagePath) {
            throw '直接復元には RestoreFromWorkspaceId を指定してください（restore-package から復元する場合は RestorePackagePath も併せて指定し、RestoreFromWorkspaceId には "restore-package" を指定します）。'
        }
        # RestorePackagePath 指定時に RestoreFromWorkspaceId を省略した場合は "restore-package" を既定値として使う
        $effectiveFromId = if ($RestoreFromWorkspaceId) { $RestoreFromWorkspaceId } else { 'restore-package' }
        Invoke-DirectRestoreMode -SourceRoot $SourceRoot -RestorePackagePath $RestorePackagePath -RestoreFromWorkspaceId $effectiveFromId -RestoreToWorkspaceId $RestoreToWorkspaceId -SessionId $SessionId -ForceRestoreOverwrite:$ForceRestoreOverwrite -IncludeStateDbIndex:$IncludeStateDbIndex
    } else {
        Invoke-ExtractMode -SourceRoot $SourceRoot -OutputRoot $OutputRoot -Since $Since -IncludeSummary:$IncludeSummary -CreateRestorePackage:$CreateRestorePackage -IncludeStateDbIndex:$IncludeStateDbIndex
    }
} catch {
    Write-Error "処理中にエラーが発生しました: $($_.Exception.Message)"
    exit 1
}
