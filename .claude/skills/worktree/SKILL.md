---
name: worktree
description: git worktreeの作成・管理・削除を支援する。「/worktree create <name>」「/worktree checkout <branch>」「/worktree delete <name>」「/worktree list」などのサブコマンドで操作する。「worktreeを作成して」「worktreeで作業したい」「並行して作業したい」「別ブランチを同時に開きたい」などのリクエスト時にもトリガーする。worktreeに関する操作を求められたら必ずこのスキルを使うこと。
---

# Worktree

git worktreeをサブコマンド形式で操作します。worktreeは常に `~/.worktrees/<name>/` に作成します。

## サブコマンド一覧

| コマンド | 説明 |
|---|---|
| `/worktree create <name>` | 新規ブランチ + worktreeを作成 |
| `/worktree checkout <branch>` | 既存ブランチのworktreeを追加 |
| `/worktree delete <name>` | worktreeを削除 |
| `/worktree list` | worktree一覧を表示 |

---

## `/worktree create <name>`

新しいブランチとworktreeを同時に作成します。

`<name>` が省略されていれば目的を聞いてブランチ名を提案する。

```bash
mkdir -p ~/.worktrees
git worktree add ~/.worktrees/<name> -b <name>
```

完了後、作業ディレクトリのフルパスを伝える。

---

## `/worktree checkout <branch>`

既存ブランチをworktreeとして追加します。

1. `<branch>` が省略されていれば `git branch` で一覧を出して選んでもらう
2. 既にチェックアウトされていないか確認する：
   ```bash
   git worktree list
   ```
   同じブランチが別のworktreeで使われていればエラーになるため、別の名前を提案する

3. worktreeを追加する：
   ```bash
   mkdir -p ~/.worktrees
   git worktree add ~/.worktrees/<branch> <branch>
   ```

完了後、作業ディレクトリのフルパスを伝える。

---

## `/worktree delete <name>`

worktreeを削除します。

1. `<name>` が省略されていれば `git worktree list` で一覧を出して選んでもらう
2. worktreeを削除する：
   ```bash
   git worktree remove ~/.worktrees/<name>
   ```
3. ブランチも削除するか確認する（マージ済みなら削除を提案する）：
   ```bash
   git branch -d <name>
   ```

**未コミットの変更がある場合**: 強制削除（`--force`）を提案するが、変更が失われることをユーザーに警告してから実行する。

---

## `/worktree list`

現在のworktree一覧を表示します。

```bash
git worktree list
```

結果を整理して、各worktreeのパスとブランチを分かりやすく表示する。

---

## サブコマンドが指定されていない場合

自然言語のリクエストの場合は意図を解釈して適切なサブコマンドを実行する。
例：「feature/loginブランチでworktreeを作って」→ `/worktree create feature/login` として処理する。

## エラー対処

- **「already checked out」**: 同じブランチは複数のworktreeで使えない。別のブランチ名を提案する
- **削除できない**: 未コミットの変更を確認。`--force` を提案するが変更消失を警告する
- **古い参照が残っている**: `git worktree prune` で整理を提案する
