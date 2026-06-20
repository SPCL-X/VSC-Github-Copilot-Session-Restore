window.__GUIDE_DATA__ = {
  "title": "VS Code Copilot Chat セッション復元ガイド",
  "steps": [
    {
      "id": "overview",
      "navLabel": "概要",
      "heading": "概要",
      "body": [
        "このツールは、VS Code の workspaceStorage に保存されている Copilot Chat セッションを抽出・要約し、必要に応じて別のワークスペースへ直接復元するための PowerShell スクリプトです。",
        "ワークスペースが保存されずにセッション履歴が見えなくなった場合の復旧や、別PC・別ユーザー環境への移植を想定しています。"
      ]
    },
    {
      "id": "requirements",
      "navLabel": "事前準備",
      "heading": "事前準備",
      "body": [
        "Windows PowerShell 5.1 以降が必要です。",
        "既定の抽出元は %APPDATA%\\Code\\User\\workspaceStorage です。VS Code を一度終了した状態で実行することを推奨します。",
        "復元先のワークスペースは、事前に一度VS Codeで開いて workspaceStorage フォルダを生成しておく必要があります。"
      ]
    },
    {
      "id": "step1-extract",
      "navLabel": "手順1: 抽出",
      "heading": "手順1: セッションの抽出",
      "body": [
        "次のコマンドで、指定日時以降のセッションを抽出し、conversation.md と index.md を生成します。",
        "-IncludeSummary を付けると、各セッションの冒頭発言を機械的に抜粋した summary.md も生成されます（AIによる要約ではありません）。"
      ],
      "command": ".\\restore_copilot_sessions.ps1 -Since \"2026-06-01\" -IncludeSummary"
    },
    {
      "id": "step1b-find-ids",
      "navLabel": "ワークスペースIDの確認",
      "heading": "ワークスペースID・セッションIDの確認",
      "body": [
        "直接復元には復元元・復元先の workspaceStorage フォルダ名(ID)が必要です。workspace.json を手動で開かなくても、次のコマンドで一覧表示できます。",
        "-ListWorkspaces は、各ワークスペースのID・元のフォルダパス・セッション数・最終更新日時を一覧表示します（最終更新日時が新しい順）。",
        "ワークスペースが決まったら -ListSessionsForWorkspaceId でそのワークスペース内のセッション一覧（先頭発言の抜粋付き）を確認できます。"
      ],
      "command": ".\\restore_copilot_sessions.ps1 -ListWorkspaces\n.\\restore_copilot_sessions.ps1 -ListSessionsForWorkspaceId \"<確認したいワークスペースID>\""
    },
    {
      "id": "step2-package",
      "navLabel": "手順2: restore-packageの作成",
      "heading": "手順2: restore-package の作成",
      "body": [
        "別PC・別環境へ移植する場合は、-CreateRestorePackage を付けて実行し、復元に必要な生データ一式をまとめた restore-package フォルダを作成します。",
        "restore-package フォルダには README_restore.md が含まれ、復元コマンド例が記載されます。"
      ],
      "command": ".\\restore_copilot_sessions.ps1 -Since \"2026-06-01\" -CreateRestorePackage"
    },
    {
      "id": "step3-restore",
      "navLabel": "手順3: 直接復元",
      "heading": "手順3: 直接復元",
      "body": [
        "復元元と復元先の workspaceStorage フォルダ名(ID)を指定すると、セッション関連ファイルを直接コピーします。IDが分からない場合は前のステップの -ListWorkspaces で確認してください。",
        "既存ファイルがある場合は既定でスキップされます。上書きするには -ForceRestoreOverwrite を指定してください。",
        "restore-package から復元する場合は -RestorePackagePath を指定し、-RestoreFromWorkspaceId には \"restore-package\" を指定します。"
      ],
      "command": ".\\restore_copilot_sessions.ps1 -RestoreFromWorkspaceId \"<元のID>\" -RestoreToWorkspaceId \"<復元先のID>\" -ForceRestoreOverwrite"
    },
    {
      "id": "step4-restart",
      "navLabel": "手順4: 復元後の再起動",
      "heading": "手順4: 復元後はVS Code完全終了→再起動",
      "body": [
        "直接復元を実行した後は、VS Codeを完全終了し、再起動してください。",
        "再起動せずにそのまま操作を続けると、セッション一覧やチャットエディタの状態が正しく反映されない場合があります。"
      ]
    },
    {
      "id": "options",
      "navLabel": "オプション一覧",
      "heading": "オプション一覧",
      "options": [
        { "name": "SourceRoot", "desc": "抽出元のworkspaceStorageフォルダ。既定は %APPDATA%\\Code\\User\\workspaceStorage。" },
        { "name": "OutputRoot", "desc": "抽出結果の出力先フォルダ。" },
        { "name": "ListWorkspaces", "desc": "ワークスペースID・元フォルダパス・セッション数・最終更新日時を一覧表示します（更新が新しい順）。" },
        { "name": "ListSessionsForWorkspaceId", "desc": "指定したワークスペースID内のセッションID一覧を、先頭発言の抜粋付きで表示します。" },
        { "name": "Since", "desc": "この日時以降に更新されたセッションのみを対象にします。" },
        { "name": "IncludeSummary", "desc": "summary.md（ヒューリスティック要約）を生成します。" },
        { "name": "CreateRestorePackage", "desc": "restore-package フォルダと README_restore.md を生成します。" },
        { "name": "RestorePackagePath", "desc": "restore-package から復元する場合の参照元パス。" },
        { "name": "RestoreFromWorkspaceId", "desc": "直接復元時の復元元ワークスペースID。" },
        { "name": "RestoreToWorkspaceId", "desc": "直接復元時の復元先ワークスペースID。指定すると直接復元モードになります。" },
        { "name": "SessionId", "desc": "直接復元時に対象セッションを絞り込みます（省略時は全件）。" },
        { "name": "ForceRestoreOverwrite", "desc": "直接復元時、既存ファイルを上書きします。" },
        { "name": "IncludeStateDbIndex", "desc": "履歴表示用の補助機能です。抽出時は index.md に履歴残存列を追加し、直接復元時は state.vscdb をバックアップ後に同期します。指定しない場合、state.vscdb には一切触れません。履歴表示の確認が必要なときだけ指定してください。" }
      ]
    },
    {
      "id": "checks",
      "navLabel": "安全運用チェック",
      "heading": "安全運用チェック",
      "checks": [
        "別PC・別ユーザー環境へ移植する際は、ファイルパスや実行環境などの文脈が元の環境と異なる可能性があります。復元したセッションの内容を文脈に応じて読み替えてください。",
        "文脈の差異が大きい場合は、復元したセッションをそのまま継続せず、必要に応じて新規セッションを開始してください。",
        "IncludeStateDbIndex は履歴表示確認のための補助機能です。state.vscdb 全体を書き換えるため、常用は避けてください。",
        "直接復元後は必ずVS Codeを完全終了し、再起動してください。"
      ]
    }
  ]
}
;
