---
name: design-flow
description: DDD設計フローを統合実行する。conceptual-modeling → class-design → table-design の3スキルをサブエージェントで順次実行し、エージェント間クロスレビューで整合性を自動検証する。blocking issueが0件になるまで最大3イテレーション繰り返し、収束後にユーザーレビューを受ける。「DDD設計フローを実行して」「設計を一括で進めて」「design-flowして」「ビジネス要件からテーブル設計まで一気にやって」「DDD設計を回して」「概念モデルからテーブルまで設計して」などのリクエスト時にトリガーする。単体のconceptual-modeling、class-design、table-designだけを求められた場合はトリガーしない。
---

# DDD 設計フロー（design-flow）

conceptual-modeling・class-design・table-design の3スキルをサブエージェントで順次実行し、エージェント間クロスレビューで成果物間の整合性を自動検証する。blocking issue が 0 件に収束するまでイテレーションを繰り返し、収束後にユーザーの最終レビューを受ける。

---

## 入力と出力

**入力:** ビジネス要求（conceptual-modelingと同じ）

ビジネス要求が不足している場合は、ユーザーにヒアリングして補完する。以下の情報が揃うまでフローを開始しない：
- 既存システムの主要な概念・BC構成
- 追加する機能のビジネス上の目的
- 機能が対象とするアクターと業務フロー

**出力:** 1つの統合設計ドキュメント（`docs/ddd/[機能名]-design.md`）

以下のセクションを含む：
1. 概念モデリング（ES結果、概念モデル図、ユビキタス言語、BC間連携マトリクス、ポリシー整合性分類）
2. クラス設計（実装クラス図、ディレクトリ構成、リードモデル構成、状態遷移図、設計判断記録）
3. テーブル設計（ER図、テーブル定義一覧、インデックス戦略、マイグレーション順序、設計判断記録）

クロスレビュー報告やフィードバック等の中間成果物はユーザーに提示しない。

---

## ワークフロー概要

```
Step 1: ビジネス要求の確認・ヒアリング
Step 2: Iteration 1 — 全フェーズ実行
  Phase A: conceptual-modeling（サブエージェント）
  Phase B: class-design（サブエージェント）
  Phase C: table-design（サブエージェント）
Step 3: クロスレビュー（3サブエージェント並列）
Step 4: 収束判定
  → blocking issue あり & iteration < 3 → Step 5 へ
  → blocking issue なし or iteration = 3 → Step 6 へ
Step 5: Iteration 2+ — 選択的再実行 → Step 3 へ戻る
Step 6: 統合ドキュメントの生成・ユーザーレビュー
```

---

## 収束の定義

クロスレビューの結果を2種類に分類する：

| 分類 | 定義 | 収束への影響 |
|---|---|---|
| **blocking issue** | 成果物間の不整合。放置すると実装時に矛盾が生じる（集約の欠落、FK/association不一致、状態値の不一致、BC境界の不整合等） | 収束をブロックする |
| **suggestion** | 改善提案。整合性に問題はないが、より良い設計にできる（命名改善、インデックス追加、パターン変更の検討等） | 収束をブロックしない。最終レビューでユーザーに提示する |

**収束条件:** 全クロスレビューの blocking issue が 0 件

**上限:** 3イテレーション。上限到達時は残存する blocking issue をユーザーに提示し、判断を委ねる。

---

## Step 1: ビジネス要求の確認

ユーザーから提供されたビジネス要求を確認し、不足があればヒアリングする。conceptual-modelingスキルの入力要件（既存システムの構成、ビジネス目的、アクター、業務フロー）が揃っていることを確認する。

この段階で **機能名**（ファイル名に使う識別子）を決定する。ユーザーに確認して合意を取る。

---

## Step 2: Iteration 1 — 全フェーズ実行

3つのフェーズを順次サブエージェントで実行する。各サブエージェントは該当スキルの SKILL.md と references/ を読み、スキルの手順に従って成果物を生成する。

各フェーズの成果物は内部的な作業ファイル（`docs/ddd/[機能名]-modeling.md` 等）として一時保存する。これらは最終的に統合ドキュメントにまとめられるため、ユーザーに個別提示しない。

### Phase A: conceptual-modeling

サブエージェントに以下を指示する：

```
あなたはDDD概念モデリングの専門家です。以下のタスクを実行してください。

1. スキル定義を読む: .claude/skills/conceptual-modeling/SKILL.md と references/ 配下のファイルをすべて読む
2. ビジネス要求: [ここにビジネス要求を貼る]
3. スキルの手順（Step 2〜Step 6）に従って概念モデリングを実行する
4. 成果物を docs/ddd/[機能名]-modeling.md に保存する

重要: スキルに定義されたAgent Teams（DE/LE/F）の議論を省略しないこと。
```

**完了確認:** 概念モデル図・ES結果・ユビキタス言語・BC間連携マトリクス・ポリシー整合性分類テーブルが含まれていること。

### Phase B: class-design

サブエージェントに以下を指示する：

```
あなたはRailsクラス設計の専門家です。以下のタスクを実行してください。

1. スキル定義を読む: .claude/skills/class-design/SKILL.md と references/ 配下のファイルをすべて読む
2. conceptual-modelingの成果物を読む: docs/ddd/[機能名]-modeling.md
3. スキルの手順（Step 1〜Step 7）に従ってクラス設計を実行する
   - Step 6（table-designとの整合性確認）はスキップする（まだtable-designの出力がないため）
4. 成果物を docs/ddd/[機能名]-class-design.md に保存する

重要: スキルに定義されたAgent Teams（A/RE/R）の議論を省略しないこと。
Serviceクラスは作成しないこと。
```

**完了確認:** 実装クラス図・ディレクトリ構成・リードモデル構成・状態遷移図・設計判断記録が含まれていること。

### Phase C: table-design

サブエージェントに以下を指示する：

```
あなたはRailsテーブル設計の専門家です。以下のタスクを実行してください。

1. スキル定義を読む: .claude/skills/table-design/SKILL.md と references/ 配下のファイルをすべて読む
2. conceptual-modelingの成果物を読む: docs/ddd/[機能名]-modeling.md
3. class-designの成果物を読む: docs/ddd/[機能名]-class-design.md
4. スキルの手順（Step 1〜Step 8）に従ってテーブル設計を実行する
   - Step 7（class-designとの整合性確認）も実行する
5. 成果物を docs/ddd/[機能名]-table-design.md に保存する

重要: スキルに定義されたAgent Teams（D/RE/R）の議論を省略しないこと。
イミュータブルデータモデリングをデフォルトの設計指向とすること。
```

**完了確認:** ER図・テーブル定義一覧・インデックス戦略・マイグレーション順序・設計判断記録が含まれていること。

---

## Step 3: クロスレビュー

3つのレビューを **並列サブエージェント** で実行する。各レビュアーは対象の成果物を読み、チェックリストに基づいて blocking issue と suggestion を分類して報告する。レビュー結果は内部的に保持し、ユーザーには提示しない。

### レビュー 1: 概念整合性レビュー

conceptual-modelingの視点から、class-design と table-design の成果物を検証する。

```
あなたはDDD概念モデリングの専門家です。以下の3つの成果物を読み、概念モデルとの整合性を検証してください。

読むファイル:
- docs/ddd/[機能名]-modeling.md（概念モデル — これが正）
- docs/ddd/[機能名]-class-design.md
- docs/ddd/[機能名]-table-design.md

チェックリスト:
1. 概念モデルの全 <<集約ルート>> が ActiveRecord クラスとテーブルの両方に存在するか
2. ESの全ドメインイベントがクラス設計に反映されているか（モデルメソッド/EventHandler）
3. ESの全コマンドがクラス設計に反映されているか（モデルメソッド/Formオブジェクト）
4. ESの全ポリシーがクラス設計とテーブル設計に反映されているか
5. ユビキタス言語の用語がクラス名・テーブル名・カラム名に一貫して使われているか
6. BC境界が namespace（クラス設計）とテーブル名プレフィックス（テーブル設計）で一致しているか
7. 集約分離の判断根拠が、クラス設計・テーブル設計の両方で尊重されているか
8. ポリシー整合性分類（強整合性/結果整合性）がクラス設計の実装方式と整合しているか

出力形式:
## blocking issues
- [番号] [チェック項目番号] 具体的な不整合の内容

## suggestions
- [番号] 改善提案の内容

blocking issue がない場合は「blocking issues: なし」と明記すること。
```

### レビュー 2: クラス→テーブル整合性レビュー

class-designの視点から、table-design の成果物を検証する（class-design Step 6 相当）。

```
あなたはRailsクラス設計の専門家です。クラス設計とテーブル設計の整合性を検証してください。

読むファイル:
- docs/ddd/[機能名]-class-design.md（クラス設計 — これが検証の基準）
- docs/ddd/[機能名]-table-design.md

チェックリスト:
1. 全 ActiveRecord model がテーブルと1:1で対応しているか
2. has_many / belongs_to がFK構造と一致しているか
3. 値オブジェクトの実装方式がテーブル設計と整合しているか
   - composed_of → 複数カラム
   - store_model → JSON型カラム
   - Data.define → テーブルに永続化しない
4. STI / delegated_types の使用がテーブル設計と一致しているか
5. 状態遷移図の状態値が enum カラムの値と一致しているか
6. リードモデルの構成元テーブルが存在するか

出力形式: レビュー1と同じ。
```

### レビュー 3: テーブル→クラス整合性レビュー

table-designの視点から、class-design の成果物を検証する（table-design Step 7 相当）。

```
あなたはRailsテーブル設計の専門家です。テーブル設計とクラス設計の整合性を検証してください。

読むファイル:
- docs/ddd/[機能名]-table-design.md（テーブル設計 — これが検証の基準）
- docs/ddd/[機能名]-class-design.md

チェックリスト:
1. 全テーブルに対応する ActiveRecord model が存在するか
2. FK構造が has_many / belongs_to と一致しているか
3. イミュータブルテーブル（INSERT-only）に対応するモデルが readonly 設計になっているか
4. CHECK制約 / enum カラムの値が状態遷移図の状態値と一致しているか
5. JSON型カラムに対応する値オブジェクトが store_model で実装されているか
6. 楽観ロック（lock_version）を持つテーブルのモデルが lock_version を使用しているか

出力形式: レビュー1と同じ。
```

---

## Step 4: 収束判定

レビュー結果のblocking issueの件数を確認する。

**blocking issue = 0 の場合:** 収束。Step 6 へ進む。

**blocking issue > 0 かつ iteration < 3 の場合:** Step 5 へ進む。ユーザーに進捗を簡潔に報告する：
- 「Iteration N 完了。blocking issue が X 件あります。修正イテレーションに入ります。」

**blocking issue > 0 かつ iteration = 3 の場合:** 上限到達。Step 6 へ進む。残存する blocking issue はユーザーに提示する。

---

## Step 5: Iteration 2+ — 選択的再実行

blocking issue の内容に基づき、再実行が必要なスキルを特定する。全スキルを再実行するのではなく、課題のあるスキルだけを再実行する。

**再実行の判断基準:**

| issue の種類 | 再実行するスキル |
|---|---|
| 概念モデルと実装の不整合（集約欠落、ポリシー未反映等） | conceptual-modeling を見直す必要があるか判断 → 概念モデル側が正しければ class-design / table-design を再実行 |
| クラス↔テーブル間の不整合（FK不一致、値オブジェクト方式不一致等） | 一方を基準として他方を修正。基準の判断は issue の内容による |
| 状態値の不一致 | class-design（状態遷移図の定義元）を基準として table-design を修正 |

**再実行時のサブエージェント指示:**

通常の指示に加え、以下を追加する：

```
【前回のクロスレビューからのフィードバック】
以下の blocking issue を解決してください：
- [具体的な issue を列挙]

前回の成果物: docs/ddd/[機能名]-[skill].md
他スキルの成果物も参照して整合性を確保すること。
```

再実行後、Step 3（クロスレビュー）に戻る。

---

## Step 6: 統合ドキュメントの生成・ユーザーレビュー

収束後（またはイテレーション上限到達後）、3つの作業ファイルを **1つの統合設計ドキュメント** にまとめる。

**統合ドキュメントの構成:**

```markdown
# [機能名] DDD設計

## 1. 概念モデリング

### 1.1 Event Storming
[ES結果 — flowchart LR]

### 1.2 概念モデル図
[概念モデル図 — classDiagram]

### 1.3 ユビキタス言語
[BC別用語テーブル]

### 1.4 BC間連携マトリクス
[連携マトリクステーブル]

### 1.5 ポリシー整合性分類
[ポリシー分類テーブル]

### 1.6 集約分離の判断根拠
[該当する場合のみ]

## 2. クラス設計

### 2.1 実装クラス図
[実装クラス図 — classDiagram]

### 2.2 ディレクトリ構成
[app/ ツリー]

### 2.3 リードモデル構成
[リードモデルテーブル]

### 2.4 状態遷移図
[状態を持つ集約ごとに — stateDiagram-v2]

### 2.5 設計判断記録
[主要な設計判断とトレードオフ]

## 3. テーブル設計

### 3.1 ER図
[ER図 — erDiagram]

### 3.2 テーブル定義一覧
[各テーブルのカラム定義]

### 3.3 インデックス戦略
[インデックス定義テーブル]

### 3.4 マイグレーション順序
[依存関係に基づく実行順]

### 3.5 設計判断記録
[イミュータブル/ミュータブル選択、正規化/非正規化の根拠等]
```

**保存先:** `docs/ddd/[機能名]-design.md`

統合ドキュメントを保存したら、作業用の個別ファイル（`-modeling.md`, `-class-design.md`, `-table-design.md`）は削除する。

ユーザーに統合ドキュメントのパスを伝え、レビューを依頼する。未解決の suggestions がある場合は簡潔にリストする。上限到達で残存する blocking issues がある場合もその旨を伝える。

---

## フェーズ順序の柔軟性

基本フローは conceptual-modeling → class-design → table-design だが、以下の場合はフェーズの順序を変更してよい：

- **テーブル設計を先にすべき場合:** 既存DBスキーマがあり、それに合わせる必要がある場合は table-design → class-design の順にする
- **conceptual-modelingを再実行すべき場合:** クロスレビューで概念モデル自体の問題が指摘された場合は、class-design/table-design より先に conceptual-modeling を再実行する
- **class-designとtable-designを交互に修正すべき場合:** 相互依存の issue がある場合は、一方を修正 → レビュー → 他方を修正のサイクルにする

順序変更の判断はクロスレビューの issue 内容に基づいて行う。
