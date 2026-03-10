---
name: permission
description: |
  Claude Code の .claude/settings.local.json の permission 設定を更新するスキル。
  以下のような場面で必ず使うこと:
  - 「〜を許可して」「allow に追加して」「allow して」
  - 「〜を拒否して」「deny に追加して」「deny して」
  - 「permission を更新して」「settings.local.json を更新して」
  - 「permission を見せて」「今の設定を確認して」「allow/deny の一覧を見せて」
  - `/permission allow <rule>`、`/permission deny <rule>`、`/permission list` の形式でも呼ばれる
  ユーザーがツールやコマンドの許可・拒否を求めたときは、このスキルを必ず使うこと。
---

# Permission スキル

`.claude/settings.local.json` の `permissions.allow` / `permissions.deny` を管理する。

## サブコマンド

```
/permission list                  # 現在のルール一覧を表示
/permission allow <rule>          # allow ルールを追加
/permission deny <rule>           # deny ルールを追加
/permission remove allow <rule>   # allow ルールを削除
/permission remove deny <rule>    # deny ルールを削除
```

サブコマンドを省略した自然言語（「git log を許可して」など）でも同様に動作する。

## ファイルの場所

以下の優先順位でファイルを特定する：

1. **プロジェクトスコープ**：カレントディレクトリの `.claude/settings.local.json`
2. **グローバルスコープ**：`~/.claude/settings.local.json`

ユーザーがスコープを明示しない場合はプロジェクトスコープを使う。

## ファイル構造

```json
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
```

ファイルが存在しない場合は上記の構造で新規作成する。
ファイルに `permissions` キーが存在しない場合は追加する。
ファイルに他のキー（`enabledPlugins` など）がある場合は保持する。

## 各コマンドの動作

### list

現在の allow / deny ルールを読み込んで表示する。

**出力例：**
```
## 現在の permission 設定（.claude/settings.local.json）

### allow
- Bash(git log *)
- Bash(npm run *)

### deny
（なし）
```

### allow / deny

指定したルールを対応する配列に追加する。

1. ファイルを読み込む（存在しない場合は空の構造を使う）
2. 重複チェック：同じルールがすでにあれば「すでに登録済みです」と伝えてスキップ
3. ルールを追加して書き込む
4. 追加後のリストを表示して確認する

### remove

指定したルールを対応する配列から削除する。
ルールが見つからない場合は「見つかりませんでした」と伝える。

## ルールの形式

Claude Code の permission は以下の形式をサポートする：

| 形式 | 例 |
|------|-----|
| ツール名 | `Read`, `Write`, `Edit` |
| Bash コマンド（完全一致） | `Bash(git status)` |
| Bash コマンド（前方一致） | `Bash(git log *)` |
| Bash コマンド（特定引数） | `Bash(git -C /path log *)` |

ユーザーがルールの形式を省略した場合（例：「git log を許可して」）は、
`Bash(git log *)` のように適切な形式に変換して確認を取ってから追加する。
