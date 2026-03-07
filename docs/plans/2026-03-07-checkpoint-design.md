# Checkpoint機能 設計書

## 概要

Claudeとの作業中に試行錯誤で方向が違うと判断したとき、分岐前の状態に戻れるcheckpoint機能。
ファイル状態と作業文脈の両方を自動で記録し、`/checkpoint undo` で復元できる。

## 要件

- **チェックポイント作成**: 自動（ユーザーが指示を送ったとき、ファイル変更前）
- **保存対象**: ファイル状態（gitオブジェクト）+ 作業文脈（何をしようとしていたか）
- **undo時の動作**: ファイル復元 + その時点の作業文脈をClaudeが把握した状態で再開
- **呼び出し方**: `/checkpoint undo` のようなコマンド形式
- **プロジェクト非汚染**: hookはユーザーレベル設定（`~/.claude/settings.json`）で管理

## アーキテクチャ

```
dotfiles/
  .claude/
    settings.json              ← hooks設定を含む（install.shで ~/.claude/ にインストール）
    skills/
      checkpoint/
        SKILL.md               ← /checkpoint スキル定義
  bin/
    checkpoint-create          ← hookから呼ばれるシェルスクリプト

各プロジェクト/
  .claude/
    checkpoints/               ← .gitignore対象
      index.json               ← チェックポイントメタデータ一覧
```

## チェックポイントのデータ構造

`index.json`:
```json
{
  "current_index": 2,
  "checkpoints": [
    {
      "id": 1,
      "timestamp": "2026-03-07T10:00:00Z",
      "trigger": "user_prompt",
      "context": "worktreeスキルを追加して",
      "git_hash": "abc123def",
      "branch": "main",
      "changed_files": []
    },
    {
      "id": 2,
      "timestamp": "2026-03-07T10:05:00Z",
      "trigger": "pre_file_change",
      "context": ".claude/skills/worktree/SKILL.md を作成",
      "git_hash": "def456ghi",
      "branch": "main",
      "changed_files": [".claude/skills/worktree/SKILL.md"]
    }
  ]
}
```

**triggerの種類:**
- `user_prompt`: ユーザーの指示（`context`に指示内容を記録）
- `pre_file_change`: ファイル変更前（`context`に変更対象ファイルを記録）

**git_hashの取得方法:**
`git stash create` を使用。stashスタックには積まないため通常のgit操作と干渉しない。

## スキルコマンド

| コマンド | 動作 |
|---------|------|
| `/checkpoint undo` | 直前のチェックポイントにファイル復元 + 文脈をClaudeに提示 |
| `/checkpoint redo` | undoを取り消して前に進む |
| `/checkpoint list` | ID・タイムスタンプ・文脈の一覧表示 |
| `/checkpoint goto <id>` | 指定IDのチェックポイントに直接ジャンプ |

## Hooks設定

`~/.claude/settings.json`（install.shでインストール）:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "command": "checkpoint-create --trigger user_prompt --context \"$CLAUDE_USER_PROMPT\""
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "command": "checkpoint-create --trigger pre_file_change --context \"$CLAUDE_TOOL_INPUT\""
      }
    ]
  }
}
```

## install.sh への追加

1. `settings.json`（hooks含む）→ `~/.claude/settings.json` にコピー（既存の仕組みを流用）
2. `bin/checkpoint-create` → `~/.local/bin/checkpoint-create` にコピー + 実行権限付与

## .gitignoreへの追加

各プロジェクトで `.claude/checkpoints/` をgitignore対象とする。
checkpoint-createスクリプトが初回実行時に `.gitignore` に自動追記する。
