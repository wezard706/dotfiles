---
name: explain-code-changes
description: Use when a reviewer needs an explanatory code review, a visual review screen, or help understanding unfamiliar application changes from user experience down to implementation details. Trigger on requests for 解説付きレビュー, 変更理解, レビュー画面, or explanations for reviewers unfamiliar with the codebase. Do not trigger for ordinary code review requests without an explanation or understanding goal.
---

# Explain Code Changes

コードベースにもアプリケーションにも詳しくないレビュワーが、ユーザー体験からコード差分へ段階的に理解できる単一HTMLを生成する。

## 役割分担

このスキルは3層に分かれている。どこを自分が書くかを取り違えないこと。

| 層 | 誰が作るか |
|---|---|
| 器（章の骨組み・CSS・コメント欄などの操作） | `assets/report-shell.html`。編集しない |
| 章の本文（要旨・ユーザー影響・全体像・変更意図の説明） | 自分がHTMLで書く |
| コード差分（タブ・左右分割diff・行への紐付け） | スクリプトがgitから生成する。差分を手で書き写さない |

**何を書くかは `assets/report-shell.html` の章コメントが定める。** 着手前に必ず読むこと。あの コメントが仕様であり、このファイルには重複して書かない。

## 必須の依存スキル

- **REQUIRED SUB-SKILL:** `code-review` — 内部品質の指摘を得る
- **REQUIRED SUB-SKILL:** `sequence-diagram` — 振る舞いの流れを追うときの探索・停止規則

内部品質の観点や処理フローの探索規則をこのスキルへ複製しない。

## ワークフロー

1. レビュー対象リポジトリの `AGENTS.md` と `CLAUDE.md`、変更ファイルを支配する追加指示を読む。`docs/ubiquitous.md` があれば読む。
2. 基準refを決める。指定がなければ `main`、次に `origin/main` を試す。解決できなければ質問する。
3. 差分スナップショットを取る。以後はこのスナップショットを正本にする。

   ```bash
   node <skill-dir>/scripts/snapshot_diff.mjs \
     --output ./tmp/explain/<slug>/diff-snapshot.json \
     --base <base-ref> \
     --exclude tmp
   ```

   `--exclude` には、レビュー対象から外すパスをカンマ区切りで渡す。`tmp` を必ず含める。
   このスキル自身の生成物が `./tmp` に残るため、指定しないと自分の出力を差分として拾う。

4. `assets/report-shell.html` の共通規約と章コメントを読む。
5. [analysis-guide.md](references/analysis-guide.md) に従って変更意図へグループ化し、ユーザー影響を確定する。
6. `code-review` を独立サブエージェントで実行する。差分だけを渡し、実装計画や変更解説を渡さない。サブエージェントが使えなければインラインで実行する。
   出力をそのまま `./tmp/explain/<slug>/code-review.md` へ保存する。要約や整形をせずに残すこと。
   このファイルは組み立ての必須入力であり、レポートにも添付される。指摘が無かった場合も、その判断を出力として残す。
7. [authoring-guide.md](references/authoring-guide.md) に従って `code-changes.json` と章断片HTMLを書く。省略する章はファイルを作らない。
8. 組み立てる。

   ```bash
   node <skill-dir>/scripts/build_report.mjs \
     --diff ./tmp/explain/<slug>/diff-snapshot.json \
     --code-changes ./tmp/explain/<slug>/code-changes.json \
     --chapters ./tmp/explain/<slug>/chapters \
     --code-review ./tmp/explain/<slug>/code-review.md \
     --title "<レポートの表題>" \
     --output ./tmp/code_review_<slug>_<timestamp>.html
   ```

9. ブラウザで開いて確認する。開けない環境では絶対パスを返す。

## 失敗したときの読み方

ビルダーは黙って成果物を劣化させず、失敗させる。

| メッセージ | 意味 |
|---|---|
| どのグループにも属さない hunk があります | 差分の取りこぼし。`code-changes.json` の `groups[].members` を埋める |
| 両方に属しています | 同じhunkを2つのグループへ入れている |
| 外部リソースを参照しています | 章断片に `https://` の参照がある。単一HTMLは外部通信できない |
| 章 "summary" は省略できません | 要旨とコード解説は必ず書く |
| code-review の出力がありません | 手順6を飛ばしている。レビューを実行して出力を保存する |

## 完了条件

- 差分を省略していない（ビルダーが保証する）
- `code-review` を実行し、その出力をレポートへ添付した（ビルダーが保証する）
- 事実・推論・不明を区別している
- 省略した章が、章コメントの省略基準に照らして妥当である
- 出力したHTMLの絶対パスを報告した
