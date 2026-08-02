---
name: explain-diff
description: コードベースにもアプリケーションにも詳しくないレビュワー向けに、コード差分を解説する単一HTMLレポートを生成する。ユーザー影響→変更の全体像→変更意図ごとのコード解説へ段階的に降りる構成で、業務フロー図（シーケンス図）とER図を添え、レビュワーが差分の行単位でコメントを残せる画面を作る。
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

3. `assets/report-template.html` の共通規約と章コメントを読む（このファイルは編集しない。何を書くかはここの章コメントが定める仕様であり、このファイルには重複して書かない）。
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

## 完了条件

- 差分を省略していない（ビルダーが保証する）
- 事実・推論・不明を区別している
- 省略した章が、章コメントの省略基準に照らして妥当である
- 出力したHTMLの絶対パスを報告した
