# 章断片の記述規約

各章の本文はHTML断片として書く。何を書くかは `assets/report-shell.html` の章コメントが定める。ここでは書き方だけを扱う。

## 置き場所

作業ディレクトリは対象リポジトリの `./tmp/explain/<slug>/` にする。`<slug>` はブランチ名から作る。

```text
tmp/explain/<slug>/
├── diff-snapshot.json     snapshot_diff.mjs が生成する
├── code-changes.json      自分で書く
├── code-review.md         code-review スキルの出力テンプレート部分だけを保存する
└── chapters/
    ├── summary.html       省略不可
    ├── user-impact.html   省略基準に当てはまれば作らない
    ├── overview.html      省略基準に当てはまれば作らない
    └── code-changes.html  省略不可
```

**章を省略するときはファイルを作らない。** 空ファイルや「該当なし」と書いたファイルを置かない。ビルダーがファイルの有無を見て、章ごとレポートから消す。

## HTML断片の書き方

`<html>` や `<body>` は書かない。章の見出し（`<h2>`）も器が持っているので書かない。本文だけを書く。

使えるのは器のCSSが用意している次の要素。独自の `<style>` や `<script>` は書かない。

| 用途 | 書き方 |
|---|---|
| 段落・箇条書き | `<p>` `<ul>` `<ol>` |
| 小見出し | `<h3>` `<h4>` |
| 変更前後の対比 | `.before-after`（下記） |
| コード片 | `<pre class="code">` |
| 折りたたみ | `<details><summary>…</summary>…</details>` |
| インラインのコード名 | `<code>` |
| 不明・未確認 | `<span class="unknown">` |

### 変更前後の対比

```html
<div class="before-after">
  <div>
    <h4>変更前</h4>
    <ul><li>退会後も公開プロフィールを閲覧できた</li></ul>
  </div>
  <div>
    <h4>変更後</h4>
    <ul><li>退会と同時に一覧からも直接URLからも見えなくなる</li></ul>
  </div>
</div>
```

### 図

Mermaidを使う。器がライブラリを同梱するので、記法だけを書く。

```html
<pre class="mermaid">
flowchart LR
  visitor[利用者] --> search[コーチを探す]
  search --> visibility{公開可否}
</pre>
```

ラベルに `<` `>` `&` `"` を使わない。Mermaidの解析が壊れる。矢印ラベルに日本語を使うときは `-- 説明 -->` の形にする。

`classDiagram` を使うときは次に注意する。

- 関係が交差するとラベルが重なって読めなくなる。関係は5本程度までに抑える
- 属性やメソッドを書かないクラスは空の区画が表示される。責務や依存ではなく単に登場人物のつながりを見せたいだけなら `flowchart` を使う

図の種類と抽象度の規約は `assets/report-shell.html` の共通規約に従う。

### レビュワーがコメントできるブロック

説明のうち、レビュワーに指摘してほしい単位へ `data-commentable` を付ける。値はレポート内で一意にする。付けた要素にコメント欄が開くようになる。

```html
<div data-commentable="impact-withdrawn-visibility">
  <h3>退会後の公開範囲</h3>
  <p>…</p>
</div>
```

必須ではない。判断が割れそうな説明にだけ付ける。

### 外部リソースは書けない

`https://` や `//` で始まる `src` `href` `url()` を書くとビルドが失敗する。画像を貼りたい場合はインラインSVGかMermaidにする。単一HTMLが外部通信しないことを機械的に守るための制約。

## code-changes.html

変更意図ごとに1つの `<section data-group="…">` を書く。`data-group` は `code-changes.json` の `groups[].id` と一致させる。タブ・差分・行コメント・品質指摘はビルダーが組み立てるので書かない。

```html
<section data-group="public-visibility">
  <p>退会したコーチの情報が退会後も他の利用者から見えていたため、公開可否の判定を <code>User</code> へ集約した。</p>
  <div class="before-after">…</div>
  <details>
    <summary>理解に必要な差分外コード: Profile.active</summary>
    <p>変更後の <code>User.publicly_visible</code> がここで合成される。</p>
    <pre class="code">scope :active, -&gt; { config_active.where(user: User.publicly_visible) }</pre>
  </details>
</section>
```

`<pre class="code">` の中身はHTMLエスケープする（`<` を `&lt;`、`>` を `&gt;`、`&` を `&amp;`）。

## code-changes.json

差分そのものは書かない。`diff-snapshot.json` から機械的に描画される。ここに書くのは、差分をどう分けて、どこに何を注記するかだけ。

```json
{
  "groups": [
    {
      "id": "public-visibility",
      "title": "退会者を公開対象から除外",
      "members": [
        { "file": "backend/app/models/user.rb", "hunks": [0] },
        { "file": "backend/app/models/profile.rb" }
      ]
    }
  ],
  "annotations": [
    { "lineId": "backend/app/models/user.rb:0:2", "text": "公開可否の入口をUserへ集約している" }
  ],
  "findings": [
    {
      "id": "finding-cache",
      "groupId": "public-visibility",
      "lineId": "backend/app/graphql/resolvers/profiles_resolver.rb:1:4",
      "severity": "critical",
      "category": "正確性",
      "title": "キャッシュ済みデータで退会状態が再評価されない",
      "detail": "キャッシュ期限まで退会者の情報を返す可能性がある。",
      "suggestion": "返却直前に公開可否を再評価する。",
      "file": "backend/app/graphql/resolvers/profiles_resolver.rb",
      "line": 24
    }
  ]
}
```

| フィールド | 意味 |
|---|---|
| `groups[].id` | `code-changes.html` の `data-group` と対応させる |
| `groups[].members[].file` | `diff-snapshot.json` の `files[].path` と完全一致させる |
| `groups[].members[].hunks` | hunkのindex配列。省略するとそのファイルの全hunk |
| `annotations[].lineId` | `diff-snapshot.json` の行ID。`<path>:<hunk>:<line>` 形式 |
| `findings[].lineId` | 対応する差分行があれば指定する。無ければ `null` にすると変更意図の先頭に出る |
| `findings[].severity` | `critical` / `warning` / `suggestion` |

### 差分は省略できない

すべてのhunkがちょうど1つのグループに属していないとビルドが失敗する。未割り当てのhunkがあれば、そのhunkを含むグループを追加するか、既存グループへ含める。意図を特定できない変更を無理に他のグループへ混ぜず、独立したグループにして説明でその旨を書く。

## 組み立て

```bash
node <skill-dir>/scripts/build_report.mjs \
  --diff ./tmp/explain/<slug>/diff-snapshot.json \
  --code-changes ./tmp/explain/<slug>/code-changes.json \
  --chapters ./tmp/explain/<slug>/chapters \
  --code-review ./tmp/explain/<slug>/code-review.md \
  --title "<レポートの表題>" \
  --output ./tmp/code_review_<slug>_<timestamp>.html
```

標準出力に出力パスと省略した章が出る。省略した章が意図と違う場合は、章ファイルの有無を確認する。

`--code-review` は必須。`code-review` スキルの出力を渡す。空ファイルではビルドが失敗する。内容はレポートのフィードバック章へ折りたたんで添付され、レビュワーが指摘の元をたどれるようにする。

**保存対象は「委譲先が返したテキスト全体」ではなく「`code-review` スキル自身の出力テンプレートに従う部分」にする。** 次のものは、たとえ委譲先の応答に含まれていても取り除く。要約や言い換えではなく、単なる混入物の除去なので「原文のまま」の原則には反しない。

- 依頼の可否や実行経路を説明する前置き（例:「以下、code-reviewスキルの出力形式でそのまま返します」）
- サブエージェント実行の枠組みが応答へ注入する実行メタ情報（`agentId`、`<usage>`、`subagent_tokens` など）

境界の見分け方: `code-review` スキルの出力テンプレートは見出し（`## コードレビュー結果` など）から始まる。それより前後にある文は `code-review.md` に含めない。
