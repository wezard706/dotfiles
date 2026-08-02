---
name: explain-diff
description: Use when a reviewer needs an explanatory walkthrough of a code diff, a visual review screen, or help understanding unfamiliar application changes from user experience down to implementation details. Trigger on requests for 解説付きレビュー, 差分の解説, 変更理解, レビュー画面, or explanations for reviewers unfamiliar with the codebase. Do not trigger for quality review requests asking what is wrong with the code — this skill explains changes, it does not judge them.
---

# Explain Diff

コードベースにもアプリケーションにも詳しくないレビュワーが、ユーザー体験からコード差分へ段階的に理解できる単一HTMLを生成する。

## 必須の依存スキル

- **REQUIRED SUB-SKILL:** `sequence-diagram` — 業務フロー図の作成。エントリポイント探索・展開/停止ルール・抽象度別のラベル規則

レポートの図は全てこのスキルの規則で作る。探索規則やラベル規則をこちらへ複製しない。

## ワークフロー

1. 基準refを決める。指定がなければ `main`、次に `origin/main` を試す。解決できなければ質問する。
2. 差分スナップショットを取る。以後はこのスナップショットを正本にする。

   ```bash
   node <skill-dir>/scripts/snapshot_diff.mjs \
     --output ./tmp/explain-diff/<slug>/diff-snapshot.json \
     --base <base-ref> \
     --exclude tmp
   ```

   `--exclude` には、レビュー対象から外すパスをカンマ区切りで渡す。`tmp` を必ず含める。
   このスキル自身の生成物が `./tmp` に残るため、指定しないと自分の出力を差分として拾う。

3. `assets/report-shell.html` の共通規約と章コメントを読む（このファイルは編集しない。何を書くかはここの章コメントが定める仕様であり、このファイルには重複して書かない）。
4. [analysis-guide.md](references/analysis-guide.md) に従って変更意図へグループ化し、ユーザー影響を確定する。
5. [authoring-guide.md](references/authoring-guide.md) に従って `code-changes.json` と章断片HTMLを書く。省略する章はファイルを作らない。
6. 組み立てる。

   ```bash
   node <skill-dir>/scripts/build_report.mjs \
     --diff ./tmp/explain-diff/<slug>/diff-snapshot.json \
     --code-changes ./tmp/explain-diff/<slug>/code-changes.json \
     --chapters ./tmp/explain-diff/<slug>/chapters \
     --title "<レポートの表題>" \
     --output ./tmp/explain_diff_<slug>_<timestamp>.html
   ```

7. ブラウザで開いて確認する。開けない環境では絶対パスを返す。

## 失敗したときの読み方

ビルダーは黙って成果物を劣化させず、失敗させる。

| メッセージ | 意味 |
|---|---|
| どのグループにも属さない hunk があります | 差分の取りこぼし。`code-changes.json` の `groups[].members` を埋める |
| 両方に属しています | 同じhunkを2つのグループへ入れている |
| 外部リソースを参照しています | 章断片に `https://` の参照がある。単一HTMLは外部通信できない |
| 章 "summary" は省略できません | 要旨とコード解説は必ず書く |

## 完了条件

- 差分を省略していない（ビルダーが保証する）
- 事実・推論・不明を区別している
- 省略した章が、章コメントの省略基準に照らして妥当である
- 出力したHTMLの絶対パスを報告した
