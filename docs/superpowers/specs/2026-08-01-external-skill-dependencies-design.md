# 外部スキル依存インストール設計

## 目的

このdotfilesが利用する外部スキルを宣言的に管理し、`install.sh`の実行時に
Codex用の`~/.agents/skills`とClaude Code用の`~/.claude/skills`へ同じ内容を
再現可能にインストールする。

外部スキルのソースはこのリポジトリへ複製せず、取得元とcommit SHAを依存定義へ
記録する。インストール途中の失敗によって、既存のインストール済みスキルを
不完全な状態にしない。

## 対象

次の外部成果物をインストール対象とする。

| 取得元 | source | インストール後のスキル名 |
|---|---|---|
| `vercel-labs/agent-skills` | `skills/composition-patterns` | `composition-patterns` |
| `vercel-labs/agent-skills` | `skills/react-best-practices` | `react-best-practices` |
| `jasim/layered-rails-skills` | `layered-rails/commands/review.md` | `layered-rails-review`の参照資料 |

`vladikk/modularity`は対象外とする。CC BY-NC-SA 4.0で提供されており、業務・
商用開発でも利用するこのdotfilesの用途と整合しないためである。

## 対象外

- 外部スキルの自動更新
- ブランチ名やタグを使った追従更新
- 推移的なスキル依存の解決
- 外部スキルの改変やフォーク
- CodexまたはClaude Codeのプラグインとしての配布
- 外部リポジトリが要求するパッケージのインストール

## 設計判断

### 理想案

CodexまたはAgent Skills標準がスキル間依存を宣言・解決し、バージョン固定、
整合性検証、更新を担う。この機構は現在提供されていないため採用できない。

### 採用案

JSON形式の依存定義と、`install.sh`から呼び出す外部スキル取得処理を実装する。
依存定義と処理を分離し、依存の追加や更新では原則としてJSONだけを変更する。

外部成果物と内製スキルから一時的なインストールイメージを組み立てる。すべての
取得と検証が成功してから、管理対象のスキルをインストール先へ反映する。

`install.sh`へ依存ごとのURLやコピー処理を直書きする案は採用しない。依存を追加する
たびに制御処理を変更する必要があり、依存関係をデータとして確認できないためである。

## ファイル構成

```text
.agents/
├── external-skill-adapters/
│   └── layered-rails-review/
│       └── SKILL.md
├── skill-dependencies.json
└── skills/
    └── ...既存の内製スキル
scripts/
└── install_external_skills.sh
install.sh
```

`external-skill-adapters`は、外部の非Skill形式をSkillへ適合させるローカル定義を
置く場所とする。Codexがリポジトリを開いた時点で未完成のスキルを検出しないよう、
`.agents/skills`の外に配置する。

## 依存定義

`.agents/skill-dependencies.json`はリポジトリ単位で取得元をまとめ、その配下に
コピーする成果物を列挙する。

```json
{
  "repositories": [
    {
      "url": "https://github.com/vercel-labs/agent-skills.git",
      "revision": "0123456789abcdef0123456789abcdef01234567",
      "artifacts": [
        {
          "source": "skills/composition-patterns",
          "destination": "composition-patterns"
        },
        {
          "source": "skills/react-best-practices",
          "destination": "react-best-practices"
        }
      ]
    },
    {
      "url": "https://github.com/jasim/layered-rails-skills.git",
      "revision": "89abcdef0123456789abcdef0123456789abcdef",
      "artifacts": [
        {
          "source": "layered-rails/commands/review.md",
          "destination": "layered-rails-review/references/upstream-review.md"
        }
      ]
    }
  ]
}
```

例示した`revision`は形式を示す架空の値である。実装時点の各デフォルトブランチの
HEADを一度だけ解決し、実際の`revision`には40桁のcommit SHAを記録する。それ以降の
更新は、内容を確認したうえでSHAを手動変更する。

`source`は取得したリポジトリのルートからの相対パス、`destination`は一時的な
スキルルートからの相対パスとする。

## `layered-rails-review`アダプター

`jasim/layered-rails-skills`の`review.md`はClaude Codeコマンドであり、
`SKILL.md`ではない。ローカルの`layered-rails-review/SKILL.md`は、インストール時に
取得される`references/upstream-review.md`を読み、そのレビュー手順、チェック項目、
重要度、出力形式に従うよう指示する。

アダプター自身には外部文書を複製しない。取得した文書が存在しなければ、完成した
スキルとして扱わずインストールを失敗させる。

## インストールフロー

1. `install.sh`が`git`と`jq`の存在を確認する。
2. `mktemp -d`で一時ディレクトリを作り、終了時の削除を`trap`へ登録する。
3. 既存の`.agents/skills`を一時スキルルートへコピーする。
4. `.agents/external-skill-adapters`を一時スキルルートへコピーする。
5. `scripts/install_external_skills.sh`が依存定義を検証する。
6. 外部リポジトリをリポジトリごとに一度だけ取得し、指定SHAをcheckoutする。
7. 各artifactを一時スキルルートの`destination`へコピーする。
8. 管理対象となる全スキルに`SKILL.md`があることを検証する。
9. `layered-rails-review`に`references/upstream-review.md`があることを検証する。
10. 両インストール先のincoming、既存内容のbackup、旧inventoryを準備する。
11. 検証済みスキルと新inventoryを両方へ反映し、旧inventoryだけにあるスキルを削除する。
12. 片方でも反映に失敗した場合は、変更を開始した全インストール先をbackupから復元する。

外部依存の取得に失敗した場合、外部スキルだけを省略して処理を続行しない。
内製スキルと外部スキルを一つの宣言済みインストール構成として扱うためである。

## インストール先への反映

利用者が別の方法でインストールしたスキルは保全する。今回の一時スキルルートに
含まれる管理対象と、前回のinventoryに記録された管理対象だけを操作する。

各インストール先の`.dotfiles-managed-skills`をdotfilesが管理するinventoryとする。
形式は、管理対象のトップレベルスキルディレクトリ名をCロケールで昇順に並べた
改行区切りテキスト（1行1スキル名）とする。前回のinventoryにあり、今回のbundleに
ないスキルは削除する。inventoryにないディレクトリは管理対象外として保全する。

既存の`cp -r`による重ね書きでは削除済みファイルが残るため、管理対象スキルの
置換時は新しいディレクトリをインストール先内のtransactionディレクトリへコピーする。
両インストール先について、今回と前回の管理対象のbackup、incoming、inventory更新を
すべて準備してから反映を始める。Codex用とClaude Code用の片方で反映に失敗した場合は、
先に反映済みのインストール先を含めて全変更を復元し、非0で終了する。旧スキルの削除と
inventory更新も同じtransactionに含める。

## 入力検証と安全性

- `revision`は40桁の16進commit SHAだけを許可する。
- `source`と`destination`は空文字、絶対パス、`.`または`..`のパス要素を拒否する。
- `destination`の重複を拒否する。
- 取得後のHEADが指定SHAと一致することを確認する。
- 外部repositoryのsource、内製スキル、adapter、bundleの出力先、両インストール先は、
  最終パスだけでなく各祖先パス要素のシンボリックリンクも拒否する。
- コピー対象のsource配下にあるシンボリックリンクも拒否する。
- ディレクトリとして配置する外部スキルには`SKILL.md`を要求する。
- `layered-rails-review`にはアダプターと外部参照の両方を要求する。
- Gitの設定やフックを実行対象にしない。
- 一時ディレクトリ外への書き込みを、最終反映処理より前には行わない。

## エラー表示

エラーには、失敗した依存のURL、revision、source、および失敗理由を含める。
認証情報を含む可能性のあるGit設定や環境変数は表示しない。

失敗時は非0で終了し、既存インストール先へ反映する前の失敗であれば、既存スキルは
変更されていないことを明示する。

## テスト

ネットワークに依存しないテストでは、ローカルにfixture Gitリポジトリを作成し、
一時的な依存定義と`HOME`を使用する。

次を検証する。

- 正常なディレクトリartifactを両方のインストール先へ配置できる。
- ファイルartifactを`layered-rails-review/references`へ配置できる。
- 同じリポジトリを参照する複数artifactで取得処理が一度だけ実行される。
- 再実行しても同じ結果になる。
- 管理対象外の既存スキルを保全する。
- 2回目の実行で依存から外れた管理対象スキルを両インストール先から削除する。
- 2つ目のインストール先への反映失敗時に、1つ目を含む全変更を復元する。
- source、bundle出力先、インストール先の祖先シンボリックリンクを拒否する。
- 不正なSHAを拒否する。
- 存在しないsourceを拒否する。
- `SKILL.md`がない外部スキルを拒否する。
- 不正な相対パスとdestination重複を拒否する。
- 検証失敗時に既存のインストール先を変更しない。

加えて、次の実環境検証を行う。

```text
bash -n install.sh scripts/install_external_skills.sh
jq empty .agents/skill-dependencies.json
外部GitHub依存を一時ディレクトリへ取得してステージング検証
```

利用者の実際の`HOME`は検証では変更しない。

## 更新手順

1. 対象リポジトリの新しいcommitを確認する。
2. 変更内容とライセンス変更の有無をレビューする。
3. `.agents/skill-dependencies.json`の`revision`を更新する。
4. ローカルfixtureテストと実GitHub依存のステージング検証を実行する。
5. 依存定義の変更をコミットする。

取得元のライセンスが商用利用と整合しなくなった場合は、更新せず依存対象から
除外する。
