# VSC GitHub Copilot Session Restore

Recover, summarize, and migrate VS Code GitHub Copilot Chat session history — entirely offline, with plain Windows PowerShell.

[English](#english) | [日本語](#日本語)

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00?logo=buymeacoffee&logoColor=000)](https://www.buymeacoffee.com/spclx)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## English

### What is this?

VS Code stores GitHub Copilot Chat session history inside `%APPDATA%\Code\User\workspaceStorage\<id>\...`. If a workspace's storage ID changes (after a crash, an unsaved workspace, a workspace move, or a fresh install), the chat history becomes invisible in the UI even though the underlying files are still on disk.

This tool finds, reads, exports, and — if you need it — restores that data, using nothing but Windows PowerShell. No external dependencies, no AI API key required.

### Features

- Extract sessions into readable `conversation.md` / `index.md`
- Offline, heuristic `summary.md` (a structural digest, not an AI summary — no API key needed)
- Build a portable `restore-package` folder for moving sessions to another PC
- Direct restore between `workspaceStorage` folders, with overwrite protection
- Built-in `-ListWorkspaces` / `-ListSessionsForWorkspaceId` commands — no need to manually open `workspace.json` files to find IDs
- `state.vscdb` is never touched unless you explicitly opt in with `-IncludeStateDbIndex`, and it is backed up first when you do
- A step-by-step guide site that works by opening the HTML file directly (`file://`), no server required

### Requirements

- Windows 10/11, Windows PowerShell 5.1 or later
- VS Code with GitHub Copilot Chat

### Quick start

```powershell
# 1. Find your workspace IDs (sorted by most recent activity)
.\restore_copilot_sessions.ps1 -ListWorkspaces

# 2. Extract sessions to Markdown
.\restore_copilot_sessions.ps1 -Since "2026-06-01" -IncludeSummary

# 3. (optional) Build a portable package to move to another PC
.\restore_copilot_sessions.ps1 -Since "2026-06-01" -CreateRestorePackage

# 4. Restore sessions directly into another workspace
.\restore_copilot_sessions.ps1 -RestoreFromWorkspaceId "<source-id>" -RestoreToWorkspaceId "<target-id>" -ForceRestoreOverwrite
```

After step 4, fully quit and restart VS Code.

### Full guide

Open [`docs/copilot-session-restore-guide/index.html`](docs/copilot-session-restore-guide/index.html) directly in any browser — it works fully offline, no server needed. Use the language switch in the top-right corner to toggle between English and Japanese.

### Safety notes

- Without `-IncludeStateDbIndex`, `state.vscdb` is never touched.
- When moving sessions to another PC or user account, file paths and execution context may differ from the original — start a new chat session if the restored context no longer matches.
- Always fully quit and restart VS Code after a direct restore.

### License

[MIT](LICENSE)

### Support

If this tool helped you recover lost chat history, consider [buying me a coffee](https://www.buymeacoffee.com/spclx) ☕

---

## 日本語

### これは何？

VS Code の GitHub Copilot Chat のセッション履歴は `%APPDATA%\Code\User\workspaceStorage\<id>\...` に保存されています。クラッシュ・ワークスペース未保存・フォルダ移動・再インストールなどでワークスペースのストレージIDが変わると、ファイル自体は残っているのにUI上はチャット履歴が見えなくなってしまいます。

このツールは、Windows PowerShellだけでそのデータを発見・抽出・要約し、必要であれば復元します。外部依存やAIのAPIキーは不要です。

### 機能

- セッションを読みやすい `conversation.md` / `index.md` に抽出
- オフラインのヒューリスティック要約 `summary.md`（AI要約ではなく構造的な抜粋。APIキー不要）
- 別PCへ移植するための `restore-package` フォルダを作成
- `workspaceStorage` フォルダ間での直接復元（上書き保護つき）
- `-ListWorkspaces` / `-ListSessionsForWorkspaceId` でID確認が可能。`workspace.json` を手動で開く必要なし
- `-IncludeStateDbIndex` を明示しない限り `state.vscdb` には一切触れず、指定した場合も事前にバックアップ
- ブラウザで直接(`file://`)開けるステップバイステップの手順書サイト付き。サーバー不要

### 必要環境

- Windows 10/11、Windows PowerShell 5.1以降
- GitHub Copilot Chat を利用しているVS Code

### クイックスタート

```powershell
# 1. ワークスペースIDを確認（最終更新が新しい順）
.\restore_copilot_sessions.ps1 -ListWorkspaces

# 2. セッションをMarkdownへ抽出
.\restore_copilot_sessions.ps1 -Since "2026-06-01" -IncludeSummary

# 3. （任意）別PCへ移植するためのパッケージを作成
.\restore_copilot_sessions.ps1 -Since "2026-06-01" -CreateRestorePackage

# 4. 別のワークスペースへ直接復元
.\restore_copilot_sessions.ps1 -RestoreFromWorkspaceId "<元のID>" -RestoreToWorkspaceId "<復元先のID>" -ForceRestoreOverwrite
```

手順4の後は、VS Codeを完全に終了して再起動してください。

### 詳しい手順書

[`docs/copilot-session-restore-guide/index.html`](docs/copilot-session-restore-guide/index.html) をブラウザで直接開いてください。完全オフラインで動作し、サーバーは不要です。右上の言語切替で日本語/Englishを切り替えられます。

### 安全に使うための注意

- `-IncludeStateDbIndex` を指定しない限り `state.vscdb` には一切触れません。
- 別PC・別ユーザー環境へ移植する場合、ファイルパスや実行環境などの文脈が元の環境と異なる可能性があります。復元した内容がその場に合わない場合は、新規セッションを開始してください。
- 直接復元のあとは必ずVS Codeを完全終了し、再起動してください。

### ライセンス

[MIT](LICENSE)

### 支援

このツールが失われたチャット履歴の復旧に役立ったら、[コーヒーをおごっていただけると](https://www.buymeacoffee.com/spclx) 嬉しいです ☕
