---
name: dev
description: backend/devコマンドを使ってgit worktreeとDockerコンテナを管理する。「/dev create <name>」「/dev up <name>」「/dev down <name>」「/dev delete <name>」「/dev list」などのサブコマンドで操作する。「worktreeのコンテナを起動して」「並行開発環境を作って」「dev upして」「devコマンドで〜」などのリクエスト時にもトリガーする。
---

# Dev

`./backend/dev` コマンドを使って git worktree と Docker コンテナを管理します。worktree は常に `worktrees/<name>/` に作成されます。

## サブコマンド一覧

| コマンド | 説明 |
|---|---|
| `/dev create <name>` | 新規ブランチ + worktree を作成 |
| `/dev checkout <branch>` | 既存ブランチの worktree を追加 |
| `/dev delete <name>` | コンテナ停止 + worktree を削除 |
| `/dev up <name>` | コンテナを起動 |
| `/dev down <name>` | コンテナを停止 |
| `/dev list` | worktree 一覧を表示 |

---

## `/dev create <name>`

新しいブランチと worktree を同時に作成します。`.env.worktree` が自動生成されます（コンテナは起動しません）。

`<name>` が省略されていれば目的を聞いてブランチ名を提案する。

実行前に現在のブランチを確認する：

```bash
git branch --show-current
```

カレントブランチが `main` でない場合、ユーザーに確認する：

> 現在のブランチは `<current_branch>` です。`main` から新規ブランチを作成しますか？

- **Yes** → `main` をベースに worktree を作成する：
  ```bash
  ./backend/dev create <name> --branch main
  ```
  ※ `--branch main` で既存の main ブランチをベースとして指定

- **No** → カレントブランチをベースにそのまま作成する：
  ```bash
  ./backend/dev create <name>
  ```

カレントブランチが `main` の場合はそのまま実行する：

```bash
./backend/dev create <name>
```

完了後、作業ディレクトリのパス（`worktrees/<name>/`）を伝え、「コンテナを起動するには `/dev up <name>` を実行してください」と案内する。

---

## `/dev checkout <branch>`

既存ブランチを worktree として追加します。

1. `<branch>` が省略されていれば `git branch` で一覧を出して選んでもらう
2. 既にチェックアウトされていないか確認する：
   ```bash
   git worktree list
   ```
   同じブランチが別の worktree で使われていればエラーになるため、別の名前を提案する

3. worktree を追加する（`--branch` で既存ブランチを指定）：
   ```bash
   ./backend/dev create <name> --branch <branch>
   ```

完了後、作業ディレクトリのパス（`worktrees/<name>/`）を伝え、「コンテナを起動するには `/dev up <name>` を実行してください」と案内する。

---

## `/dev delete <name>`

コンテナを停止してから worktree を削除します。

1. `<name>` が省略されていれば `./backend/dev list` で一覧を出して選んでもらう
2. コンテナ停止 + worktree 削除を実行する：
   ```bash
   ./backend/dev delete <name>
   ```
   （スクリプト内でブランチ削除を確認するプロンプトが表示される）

**未コミットの変更がある場合**: スクリプトが `--force` で強制削除する。変更が失われることを事前にユーザーへ警告する。

---

## `/dev up <name>`

指定した worktree のコンテナ（backend / redis / sidekiq）を起動します。DB は共有のため起動しません。

```bash
./backend/dev up <name>
```

起動後、アクセス URL（例: `http://localhost:3011`）を伝える。

---

## `/dev down <name>`

指定した worktree のコンテナを停止します。main の DB には影響しません。

```bash
./backend/dev down <name>
```

---

## `/dev list`

現在の worktree 一覧とコンテナの稼働状況を表示します。

```bash
./backend/dev list
```

結果を整理して、各 worktree のポートと状態を分かりやすく表示する。

---

## サブコマンドが指定されていない場合

自然言語のリクエストは意図を解釈して適切なサブコマンドを実行する。
例：「feature/login ブランチで worktree を作って」→ `/dev checkout feature/login` として処理する。

> **注意**: ブランチ名に `#` は使えません。`-` を使ってください（例: `feature-123` ← `feature/#123` は不可）。

## エラー対処

- **「already checked out」**: 同じブランチは複数の worktree で使えない。別のブランチ名を提案する
- **削除できない**: 未コミットの変更を確認。`--force` を提案するが変更消失を警告する
- **古い参照が残っている**: `git worktree prune` で整理を提案する
