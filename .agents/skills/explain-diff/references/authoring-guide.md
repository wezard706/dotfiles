# 章断片の記述規約

各章の本文はHTML断片として書く。何を書くかは `assets/report-shell.html` の章コメントが定める。ここでは書き方だけを扱う。

## 置き場所

作業ディレクトリは対象リポジトリの `./tmp/explain-diff/<slug>/` にする。`<slug>` はブランチ名から作る。

```text
tmp/explain-diff/<slug>/
├── diff-snapshot.json     snapshot_diff.mjs が生成する
├── code-changes.json      自分で書く
└── chapters/
    ├── summary.html       省略不可
    ├── user-impact.html   省略基準に当てはまれば作らない
    ├── overview.html      省略基準に当てはまれば作らない
    └── code-changes.html  省略不可
```

**章を省略するときはファイルを作らない。** 空ファイルや「該当なし」と書いたファイルを置かない。ビルダーがファイルの有無を見て、章ごとレポートから消す。

## HTML断片の書き方

`<html>` や `<body>` は書かない。章の見出し（`<h2>`）もテンプレートが持っているので書かない。本文だけを書く。

使えるのはテンプレートのCSSが用意している次の要素。独自の `<style>` や `<script>` は書かない。

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

Mermaidを使う。テンプレートがライブラリを同梱するので、記法だけを書く。**どの種類をどの章で使うかは `assets/report-shell.html` の共通規約が定める。ここでは書き方だけを扱う。**

```html
<pre class="mermaid">
sequenceDiagram
  participant U as 利用者
  participant API as APIサーバー
  U ->> API: コーチ一覧を開く
  API -->> U: 公開中のコーチ
</pre>
```

ラベルに `<` `>` `&` `"` を使わない。Mermaidの解析が壊れる。

#### 変更前後の並べ方

業務フロー図とER図は変更前後の2枚を並べる。`.before-after` は横2列なので図には狭すぎる。**図は `<h4>` で区切って縦に積む。**

変更後の図では、この変更で増えた・変わったやり取りを `rect` で囲んで塗る。2枚を見比べる負担が減る。

```html
<h4>変更前</h4>
<pre class="mermaid">
sequenceDiagram
  participant U as 利用者
  participant API as APIサーバー
  participant DB as データベース
  U ->> API: コーチ一覧を開く
  API ->> DB: 公開設定が有効なコーチを取得
  DB -->> API: コーチ一覧
  API -->> U: 一覧を表示
</pre>
<h4>変更後</h4>
<pre class="mermaid">
sequenceDiagram
  participant U as 利用者
  participant API as APIサーバー
  participant DB as データベース
  U ->> API: コーチ一覧を開く
  rect rgb(230, 255, 236)
    API ->> DB: 公開設定が有効かつ在籍中のコーチを取得
    DB -->> API: 退会者を除いたコーチ一覧
  end
  API -->> U: 一覧を表示
</pre>
```

`rect` は `sequence-diagram` スキルではトランザクション境界にも使う。同じ図で両方を示すときは `Note` でどちらの意味かを添える。

`flowchart` 系の図（補助として使う `stateDiagram-v2` 等）では `rect` ではなく `classDef` を使う。

```html
<pre class="mermaid">
classDiagram
  class User {
    +publicly_visible()
  }
  User --> Profile
  cssClass "User" added
</pre>
```

`classDiagram` では `class` 文が定義と衝突するため、上のように `cssClass` を使う。

#### E2Eを保ったまま詳細を書く

変更意図ごとの図は、利用者から始めて終点まで通したうえで、**この変更が触れる区間だけを展開し、関係しない区間は1メッセージへまとめる**。全体像の図と同じ言葉を使えば、レビュワーはこの図が地図のどこに当たるかを一目で結び付けられる。

```html
<pre class="mermaid">
sequenceDiagram
  participant U as 利用者
  participant C as ProfilesController
  participant M as User
  participant P as Profile
  participant DB
  U ->> C: コーチ一覧を開く
  rect rgb(230, 255, 236)
    C ->> M: publicly_visible
    M ->> P: active スコープを合成
    P ->> DB: 在籍中ユーザーに絞って取得
    DB -->> P: 対象のプロフィール
    P -->> C: 公開可能なプロフィール
  end
  C -->> U: 一覧を表示
</pre>
```

最初と最後の `U` とのやり取りは、この変更に関係しないがE2Eを成立させるために残している。逆に `C` から `DB` までは変更が触れる区間なので、クラス間の往復まで展開している。

#### 種類ごとの落とし穴

| 種類 | 注意 |
|---|---|
| `sequenceDiagram` | participant が8を超えると横に伸びて読めなくなる。登場人物を減らすのではなく、関係の薄い区間を1メッセージへ畳んで圧縮する（E2Eは崩さない）。`participant U as 利用者` の形で日本語の別名を付ける |
| `erDiagram` | 関連の基数（`\|\|--o{` 等）を省略できない。差分から確信を持てないなら、関連線を引かずテーブルを並べるだけにする |
| `classDiagram` | 関係が交差するとラベルが重なって読めなくなる。関係は5本程度まで。属性やメソッドを書かないクラスは空の区画が出る |
| `stateDiagram-v2` | 開始・終了は `[*]` で書く。状態名に日本語を使うなら `s1 : 公開中` の形で別名を付ける |
| `block-beta` | 桁数を `columns` で明示しないと崩れる |

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

変更意図ごとに1つの `<section data-group="…">` を書く。`data-group` は `code-changes.json` の `groups[].id` と一致させる。タブ・差分・行コメントはビルダーが組み立てるので書かない。

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
  ]
}
```

| フィールド | 意味 |
|---|---|
| `groups[].id` | `code-changes.html` の `data-group` と対応させる |
| `groups[].members[].file` | `diff-snapshot.json` の `files[].path` と完全一致させる |
| `groups[].members[].hunks` | hunkのindex配列。省略するとそのファイルの全hunk |
| `annotations[].lineId` | `diff-snapshot.json` の行ID。`<path>:<hunk>:<line>` 形式 |

`annotations` は、その行が何をしているかコードだけでは追いにくいときに添える一行注記。良し悪しの判定は書かない（[analysis-guide.md](analysis-guide.md) の「品質の判定は行わない」）。

### 差分は省略できない

すべてのhunkがちょうど1つのグループに属していないとビルドが失敗する。未割り当てのhunkがあれば、そのhunkを含むグループを追加するか、既存グループへ含める。意図を特定できない変更を無理に他のグループへ混ぜず、独立したグループにして説明でその旨を書く。

## 組み立て

```bash
node <skill-dir>/scripts/build_report.mjs \
  --diff ./tmp/explain-diff/<slug>/diff-snapshot.json \
  --code-changes ./tmp/explain-diff/<slug>/code-changes.json \
  --chapters ./tmp/explain-diff/<slug>/chapters \
  --title "<レポートの表題>" \
  --output ./tmp/explain_diff_<slug>_<timestamp>.html
```

標準出力に出力パスと省略した章が出る。省略した章が意図と違う場合は、章ファイルの有無を確認する。
