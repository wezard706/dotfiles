# DDD概念 → Railsテーブル設計 マッピングガイド

## このドキュメントの目的

conceptual-modelingスキルの出力（概念モデル・Event Storming結果）をRailsのテーブル設計にマッピングするためのルール集。class-designスキルの `ddd-to-rails-mapping.md` がクラス設計のマッピングを扱うのに対し、本ドキュメントはテーブル構造・制約・インデックスの設計判断を扱う。

---

## マッピングルール一覧

| DDD概念 | テーブル設計 | 判断基準 |
|---|---|---|
| 集約ルート | メインテーブル | 常に |
| エンティティ | 子テーブル（FKで親に紐づく） | 独自ライフサイクルあり |
| 値オブジェクト（単純） | 親テーブルのカラム群 | 永続化が必要で単純 |
| 値オブジェクト（複雑） | 埋め込みJSON / 参照テーブル | 構造が複雑 or 再利用 |
| 列挙型（固定） | string/integerカラム + CHECK制約 | 値が変わらない |
| 列挙型（可変） | 参照テーブル | マスタデータ |
| 多対多関連 | 中間テーブル | 常に |
| BC境界 | テーブル名プレフィックス or スキーマ | BC間の参照はIDのみ |
| ドメインイベント | イベントテーブル（INSERT-only） | イミュータブル |
| 状態遷移 | 状態テーブル + 履歴テーブル or イベントソーシング | 履歴要否で判断 |

---

## 値オブジェクトの永続化判断フロー

概念モデルの `<<値オブジェクト>>` をテーブル設計に反映する際、以下のフローで永続化方式を決定する。

```
値オブジェクトか？
  ├── 永続化不要
  │   → Rubyオブジェクトのみ（テーブル設計対象外）
  │     例: 計算結果、一時的な値の組み合わせ
  │
  └── 永続化必要
      ├── 2-3カラムで表現できる単純な構造
      │   → 親テーブルのカラム群
      │     例: address_prefecture, address_city, address_street
      │     命名: [値オブジェクト名]_[属性名] のプレフィックス形式
      │
      ├── 構造が複雑（ネストあり・属性が多い）
      │   → jsonbカラム（store_model gem活用）
      │     例: metadata jsonb NOT NULL DEFAULT '{}'
      │     注意: jsonb内の値に対するクエリが頻繁なら正規化を検討
      │
      ├── 複数テーブルから参照される
      │   → 参照テーブル（immutable）
      │     例: currencies, countries
      │     特徴: UPDATE不可、INSERT-onlyまたはシードデータ
      │
      └── 有限の選択肢（3〜10程度）
          → enum（string/integer） + CHECK制約
            例: status string NOT NULL CHECK (status IN ('active', 'inactive'))
```

---

## 正規化 vs 非正規化の判断基準

テーブル設計において正規化と非正規化のどちらを選択するかは、データの更新パターンと集約境界に基づいて判断する。

| 状況 | 推奨 | 理由 |
|---|---|---|
| 更新頻度が高い | 正規化 | 更新異常の防止 |
| 参照のみ（レポート等） | 非正規化OK | 読み取り性能 |
| 集約境界を跨ぐ | 非正規化（スナップショット） | 集約の独立性確保 |
| BC間のデータ共有 | IDのみ参照 | BC独立性 |

### 集約境界を跨ぐスナップショットの例

注文（Orders BC）が商品名を保持する場合、商品テーブル（Products BC）をJOINするのではなく、注文時点の商品名をスナップショットとしてorder_itemsテーブルに保存する。

```
order_items
  ├── product_id (bigint, NOT NULL)       -- IDのみ参照
  ├── product_name (string, NOT NULL)     -- スナップショット
  ├── unit_price (integer, NOT NULL)      -- スナップショット（注文時点の価格）
  └── quantity (integer, NOT NULL)
```

これにより、Products BCで商品名や価格が変更されても、過去の注文データは影響を受けない。

---

## Rails規約

テーブル設計はRailsの規約に従う。規約から外れる場合は明示的に記載する。

### 命名規則

| 要素 | 規約 | 例 |
|---|---|---|
| テーブル名 | 複数形スネークケース | `users`, `order_items` |
| 主キー | `id` (bigint, auto increment) | UUIDの場合は明示的に記載 |
| タイムスタンプ | `created_at`, `updated_at` | `t.timestamps` |
| 外部キー | `[テーブル名単数形]_id` | `user_id`, `order_id` |
| Polymorphic | `[名前]_type` + `[名前]_id` | `commentable_type`, `commentable_id` |

### 特殊カラム

| カラム | 用途 | 備考 |
|---|---|---|
| `type` | STI（単一テーブル継承） | ただし `delegated_types` を推奨 |
| `discarded_at` | 論理削除（discard gem） | `deleted_at` も可 |
| `lock_version` | 楽観ロック | `integer, default: 0` |

### UUIDを主キーにする場合

UUIDを採用する判断基準:
- BC間で共有されるIDで、連番を外部に露出したくない場合
- 分散システムでID生成を各ノードで行う必要がある場合

```ruby
# マイグレーション例
create_table :orders, id: :uuid do |t|
  t.timestamps
end
```

---

## 制約の種類と使い分け

データベース制約はドメインの不変条件をデータ層で保証する手段。アプリケーションバリデーションだけでなく、DB制約も併用することで整合性を担保する。

| 制約 | 用途 | マイグレーション記法例 |
|---|---|---|
| NOT NULL | 必須カラム | `null: false` |
| UNIQUE | 一意性保証 | `unique: true`（複合ユニークも可） |
| CHECK | 値の範囲・条件 | `CHECK (status IN ('active', 'inactive'))` |
| FK | 参照整合性 | `foreign_key: true` |
| DEFAULT | デフォルト値 | `default: 0` |
| INDEX | 検索性能 | `index: true`（複合/partial含む） |

### 制約の適用判断フロー

```
カラムの制約を決定する
  ├── ドメインモデルで必須属性か？
  │   └── YES → NOT NULL
  │
  ├── 一意性が求められるか？
  │   ├── 単一カラム → UNIQUE INDEX
  │   └── 複数カラムの組み合わせ → 複合UNIQUE INDEX
  │
  ├── 値の範囲・条件に制限があるか？
  │   └── YES → CHECK制約
  │     例: CHECK (amount >= 0)
  │     例: CHECK (status IN ('pending', 'active', 'canceled'))
  │
  ├── 他テーブルを参照するか？
  │   ├── 集約内の親子関係 → FK制約あり
  │   └── 集約境界を越える参照 → FK制約なし（IDのみ保持）
  │
  └── 主要な検索パターンに含まれるか？
      ├── WHERE句で頻繁に使用 → INDEX
      ├── ORDER BYで使用 → INDEX
      └── 複数カラムの組み合わせ → 複合INDEX（カーディナリティの高い順）
```

### FK制約と集約境界の関係

集約内の参照にはFK制約を設定する。集約境界を越える参照にはFK制約を設定しない。

```
集約内（FK制約あり）:
  orders → order_items  (foreign_key: true, dependent: :destroy)

集約境界を越える（FK制約なし）:
  order_items.product_id → products.id  (FK制約なし、IDのみ保持)
```

理由: 集約境界を越えたFK制約を設定すると、集約の独立したライフサイクル管理が阻害される。例えば、商品を削除する際に注文データの制約違反が発生する。

### Partial Index

特定の条件に一致する行のみにインデックスを作成する。論理削除やステータスフィルタに有効。

```ruby
# 論理削除されていないレコードのみ
add_index :users, :email, unique: true, where: "discarded_at IS NULL"

# アクティブなサブスクリプションのみ
add_index :subscriptions, :user_id, where: "status = 'active'"
```

---

## 楽観ロックの判断基準

`lock_version` カラム（integer, default: 0）を追加するかどうかの判断基準。

### 追加するケース

- **同時編集の可能性がある集約ルート** -- 複数のユーザーが同じレコードを編集しうる場合（例: 注文、プロジェクト設定）
- **ステータス遷移を持つエンティティ** -- 遷移の衝突を防止する必要がある場合（例: 承認フロー、ワークフロー）
- **フォーム経由で更新されるレコード** -- ユーザーがフォームを開いてから送信するまでの間に、他のユーザーが更新する可能性がある場合

### 不要なケース

- **INSERT-onlyのイベントテーブル** -- 更新が発生しないため衝突しない
- **管理者のみが更新するマスタデータ** -- 同時編集の可能性が極めて低い
- **バッチ処理で排他制御が別途ある場合** -- 行ロックやアドバイザリーロックで制御済み

### マイグレーション例

```ruby
create_table :orders do |t|
  t.integer :lock_version, null: false, default: 0
  t.timestamps
end
```

Railsは `lock_version` カラムが存在すれば自動的に楽観ロックを適用する。明示的な設定は不要。

---

## イベントテーブルの設計

ドメインイベントをテーブルに永続化する場合、INSERT-onlyのイミュータブルテーブルとして設計する。

### 設計原則

- UPDATE/DELETEは行わない（INSERT-only）
- `updated_at` は不要（`created_at` のみ）
- `lock_version` は不要
- 論理削除は行わない

### テーブル構造例

```
domain_events
  ├── id (bigint, PK)
  ├── event_type (string, NOT NULL)        -- 例: 'OrderPlaced', 'PaymentCompleted'
  ├── aggregate_type (string, NOT NULL)    -- 例: 'Order', 'Subscription'
  ├── aggregate_id (bigint, NOT NULL)      -- 対象集約のID
  ├── payload (jsonb, NOT NULL)            -- イベントデータ
  ├── metadata (jsonb, DEFAULT '{}')       -- トレース情報等
  ├── occurred_at (datetime, NOT NULL)     -- イベント発生時刻
  └── created_at (datetime, NOT NULL)      -- レコード挿入時刻
```

### インデックス

```ruby
add_index :domain_events, [:aggregate_type, :aggregate_id, :occurred_at]
add_index :domain_events, [:event_type, :occurred_at]
```

---

## 状態遷移の永続化パターン

状態遷移をどのように永続化するかは、履歴の要否で判断する。

```
状態遷移があるか？
  ├── 現在の状態のみ必要（履歴不要）
  │   → メインテーブルの statusカラム + CHECK制約
  │     例: orders.status CHECK (status IN ('pending', 'confirmed', 'shipped'))
  │
  ├── 遷移履歴が必要
  │   ├── 誰が・いつ・何に変更したかを追跡
  │   │   → メインテーブルの statusカラム + 履歴テーブル
  │   │     例: orders.status + order_status_histories
  │   │
  │   └── 完全な監査証跡が必要
  │       → イベントソーシング（イベントテーブルから現在状態を導出）
  │
  └── 複数の状態が独立して遷移する
      → 状態ごとに別カラム or 別テーブル
        例: payment_status, shipping_status を分離
```

### 履歴テーブルの構造例

```
order_status_histories
  ├── id (bigint, PK)
  ├── order_id (bigint, NOT NULL, FK)
  ├── from_status (string)                 -- NULLは初期状態
  ├── to_status (string, NOT NULL)
  ├── changed_by_id (bigint)               -- 変更者
  ├── reason (text)                        -- 変更理由（任意）
  └── created_at (datetime, NOT NULL)      -- updated_at は不要（INSERT-only）
```

---

## チェックリスト

テーブル設計の最終確認用。すべての項目を満たしているかを確認してからマイグレーションファイルの生成に進む。

- [ ] 全集約ルートにテーブルがあるか
- [ ] 値オブジェクトの永続化方式は妥当か（カラム群 / jsonb / 参照テーブル / enum）
- [ ] NOT NULL制約はドメインの必須属性と一致しているか
- [ ] FK制約は集約内の参照に限定されているか（集約境界を越えないこと）
- [ ] インデックスは主要な検索パターンをカバーしているか
- [ ] BC間の参照はIDのみか（テーブルJOINしていないか）
- [ ] イミュータブル/ミュータブルの分類は妥当か
- [ ] 楽観ロックの要否が判断されているか
- [ ] CHECK制約で列挙値やドメインの不変条件が保護されているか
- [ ] マイグレーション順序は依存関係に沿っているか（FK先のテーブルが先に作成されること）
