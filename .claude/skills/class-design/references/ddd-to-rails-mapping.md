# DDD概念 → Rails実装 マッピングガイド

## このドキュメントの目的

conceptual-modelingスキルの出力（概念モデル・Event Storming結果）をRailsの実装クラスにマッピングするためのルール集。

---

## マッピング一覧

| DDD概念 | Rails実装 | 判断基準 |
|---|---|---|
| 集約ルート | ActiveRecord model | 常に |
| エンティティ | ActiveRecord model（集約内） | 独自ライフサイクルあり |
| 値オブジェクト | `Data.define` / `composed_of` / embedded | 永続化要否で判断 |
| 列挙型 | `enum` / state_machines gem | 遷移ルールの複雑さで判断 |
| コマンド（単一集約） | モデルメソッド | 単一集約の操作 |
| コマンド（複数モデル） | Form object / モデルメソッド | 複数モデルの更新・外部連携あり |
| ポリシー（強整合性） | モデルメソッド | 同一トランザクション |
| ポリシー（結果整合性） | ActiveJob + EventHandler | 非同期 |
| リードモデル | Query object / DB view | 複雑さで判断 |
| 外部システム | Gateway / Adapter | Infrastructure層 |
| BC境界 | `module Namespace` | 常に |

---

## 集約ルート・エンティティ

### 集約ルート → ActiveRecord model

概念モデルの `<<集約ルート>>` は、そのまま ActiveRecord model になる。

**ルール:**
- 1集約ルート = 1 ActiveRecord model = 1テーブル
- BC境界に応じた namespace（module）配下に置く
- 集約内の他エンティティへのアクセスは集約ルート経由に限定する（`has_many` は `dependent: :destroy` が基本）
- 不変条件は `validate` で表現する

**例:**
```ruby
# 概念モデル: サブスクリプション <<集約ルート>>
# BC: Billing
module Billing
  class Subscription < ApplicationRecord
    # ...
  end
end
```

### エンティティ → ActiveRecord model（集約内）

概念モデルの `<<エンティティ>>` は、集約ルートに所有される ActiveRecord model。

**判断基準:**
- 独自の同一性（ID）を持つ → 別テーブル・別モデル
- 集約ルートと同一トランザクションで更新される

---

## 値オブジェクト

概念モデルの `<<値オブジェクト>>` のRails実装には3つの選択肢がある。

### 判断フロー

```
値オブジェクトか？
  ├── DBに永続化不要 → Data.define
  ├── DBに永続化必要
  │   ├── 単一テーブルのカラムに埋め込める → composed_of
  │   └── JSON形式で保存 → store_model gem / ActiveRecord::Store
  └── 独立テーブルが必要（参照テーブル） → ActiveRecord model（ただしimmutable）
```

### Data.define（永続化不要）

**使う場面:** 計算結果、一時的な値の組み合わせ、ドメインロジックの引数・戻り値

```ruby
Money = Data.define(:amount, :currency) do
  def +(other)
    raise "Currency mismatch" unless currency == other.currency
    self.class.new(amount: amount + other.amount, currency: currency)
  end
end
```

### composed_of（カラム埋め込み）

**使う場面:** 既存テーブルの複数カラムを1つの値オブジェクトとして扱う

```ruby
class Subscription < ApplicationRecord
  composed_of :billing_cycle,
    class_name: "BillingCycle",
    mapping: [%w[cycle_unit unit], %w[cycle_interval interval]]
end
```

### store_model gem（JSON保存）

**使う場面:** 構造化データをJSON型カラムに保存する

```ruby
class Plan
  include StoreModel::Model
  attribute :name, :string
  attribute :amount, :integer
  attribute :cycle, :string
  validates :amount, numericality: { greater_than: 0 }
end
```

---

## 列挙型

概念モデルの `<<列挙型>>` の実装は、状態遷移の複雑さで判断する。

### 判断フロー

```
列挙型か？
  ├── 状態遷移がない（単なる分類） → Rails enum
  ├── 状態遷移がある
  │   ├── 遷移ルールが単純（3〜4遷移以下） → Rails enum + バリデーション
  │   └── 遷移ルールが複雑（ガード条件・コールバックあり） → state_machines gem / workflow gem
  └── 外部から値が追加される可能性 → 参照テーブル（ActiveRecord model）
```

### Rails enum（単純なケース）

```ruby
class Subscription < ApplicationRecord
  enum :status, {
    pending: "pending",
    active: "active",
    canceled: "canceled"
  }, prefix: true

  # 遷移ルールが単純ならバリデーションで表現
  validate :validate_status_transition, if: :status_changed?

  private

  VALID_TRANSITIONS = {
    "pending" => %w[active canceled],
    "active" => %w[canceled],
    "canceled" => []
  }.freeze

  def validate_status_transition
    from = status_was
    return if VALID_TRANSITIONS[from]&.include?(status)
    errors.add(:status, "cannot transition from #{from} to #{status}")
  end
end
```

### state_machines gem / workflow gem（複雑なケース）

**使う場面:**
- ガード条件がある（「残日数が足りる場合のみ承認可能」）
- 遷移時のコールバックが必要
- 複数の遷移パスが存在

---

## コマンド → モデルメソッド / Form object

ESのコマンドをRailsに実装する際の判断。**Serviceクラスは作成しない。** ドメインロジックはモデルに配置する。

### 判断フロー

```
コマンドか？
  ├── 単一集約のみ操作
  │   → モデルメソッド
  ├── 複数モデルの更新・外部連携あり
  │   ├── ユーザー入力を受け取る → Form object
  │   └── ユーザー入力なし（内部処理） → 集約ルートのモデルメソッド（Gateway注入）
  └── 非同期処理
      → ActiveJob（Jobクラス）
```

### モデルメソッド（単一集約）

```ruby
class Subscription < ApplicationRecord
  def cancel!
    raise "Already canceled" if status_canceled?
    update!(status: :canceled, canceled_at: Time.current)
  end
end
```

### モデルメソッド + Gateway注入（外部連携）

外部システムとの連携が必要な場合も、ロジックはモデルに置く。Gatewayは引数で注入する。

```ruby
module Billing
  class Subscription < ApplicationRecord
    def activate!(gateway: PaymentGateway.new)
      ActiveRecord::Base.transaction do
        result = gateway.charge(amount: plan.amount, currency: "jpy")
        update!(status: :active, payment_id: result.id)
      end
    end
  end
end
```

### Form object（複数モデルの更新 + ユーザー入力）

ユーザー入力のバリデーションと複数モデルの更新を束ねる。

```ruby
module Billing
  class SubscriptionForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :plan_id, :integer
    attribute :coach_id, :integer

    validates :plan_id, :coach_id, presence: true

    def save
      return false unless valid?

      ActiveRecord::Base.transaction do
        subscription = Subscription.create!(plan: plan, coach: coach, status: :pending)
        subscription.activate!
      end
    end

    private

    def plan = Plan.find(plan_id)
    def coach = Coach.find(coach_id)
  end
end
```

---

## ポリシー → 整合性別の実装

ESのポリシー（「〜されたら〜する」）は、conceptual-modelingの「ポリシー整合性分類テーブル」に基づいて実装を選択する。

### 強整合性（同一トランザクション）

同じトランザクション内で完結する必要がある場合。

**実装パターン:**

| パターン | 使う場面 |
|---|---|
| モデルメソッド内で直接呼び出し | 同一集約内の連鎖 |
| 集約ルートのモデルメソッド | 同一BC内・複数集約 |
| Form object | BC間だが即座の一貫性が必要 |

```ruby
# 同一集約内: モデルメソッドで直接
class LeaveRequest < ApplicationRecord
  def approve!(approver:)
    ActiveRecord::Base.transaction do
      update!(status: :approved, approved_by: approver)
      leave_balance.consume!(days: requested_days)  # 強整合性
    end
  end
end
```

### 結果整合性（非同期）

遅延が許容される場合。

**実装パターン:**

| パターン | 使う場面 |
|---|---|
| ActiveJob | 単発の非同期処理 |
| EventHandler + ActiveJob | イベント駆動の連鎖 |
| Pub/Sub（ActiveSupport::Notifications等） | 複数のサブスクライバ |

```ruby
# 結果整合性: ActiveJob で非同期
class LeaveRequest < ApplicationRecord
  after_commit :notify_attendance, on: :update, if: :saved_change_to_status?

  private

  def notify_attendance
    return unless status == "approved"
    SyncAttendanceJob.perform_later(id)
  end
end
```

---

## リードモデル → Query object / DB view

ESのリードモデルは、アクターが意思決定のために参照するデータのビュー。

### 判断フロー

```
リードモデルか？
  ├── 単一モデルの絞り込み → scope で十分
  ├── 複数モデルの結合 + フィルタリング
  │   ├── パフォーマンスが重要 → DB view + ActiveRecord model
  │   └── 柔軟性が重要 → Query object
  └── BC間のデータ集約 → 専用Query object + キャッシュ検討
```

### Query object

```ruby
module Billing
  class SubscriptionDashboardQuery
    def initialize(coach:)
      @coach = coach
    end

    def call
      Subscription
        .where(coach: @coach)
        .includes(:plan)
        .select("subscriptions.*, plans.name as plan_name")
    end
  end
end
```

**命名規則:** 名詞 + Query（例: `SubscriptionDashboardQuery`, `LeaveBalanceSummaryQuery`）

---

## 外部システム → Gateway / Adapter

概念モデルの `<<外部システム>>` は Infrastructure 層に配置する。

### パターン

```ruby
# Gateway: 外部APIの抽象化
module Billing
  class PaymentGateway
    def charge(amount:, currency:)
      # Stripe API 呼び出し
    end

    def refund(payment_id:)
      # ...
    end
  end
end
```

**配置:** `app/gateways/` または `app/infrastructure/`

---

## BC境界 → Module / Namespace

概念モデルのBC境界は、Railsの module（namespace）に直接マッピングする。

```
BC: 請求管理 → module Billing
BC: 勤怠管理 → module Attendance
BC: 休暇管理 → module Leave
```

**ディレクトリ構成例:**
```
app/
  models/
    billing/
      subscription.rb
      plan.rb
    leave/
      leave_request.rb
      leave_balance.rb
  forms/
    billing/
      subscription_form.rb
  queries/
    billing/
      subscription_dashboard_query.rb
```

---

## layered-rails スキルとの関係

レイヤー配置の詳細な判断には `layered-rails` スキルのパターンカタログを参照すること。特に以下のパターンが関連する:

- **Form objects** — 複数モデルの更新操作
- **Query objects** — リードモデルの実装判断
- **Value objects** — 値オブジェクトの実装選択
- **State machines** — 列挙型の実装判断
- **Concerns** — 共通ドメイン振る舞いの抽出
- **Policy objects** — 認可ロジックの配置

---

## チェックリスト

マッピング完了後に確認する:

- [ ] すべての集約ルートが ActiveRecord model にマッピングされている
- [ ] 値オブジェクトの実装方式（Data.define / composed_of / store_model）が根拠とともに選択されている
- [ ] 列挙型の実装方式（enum / state_machines）が遷移の複雑さに基づいて選択されている
- [ ] コマンドがモデルメソッド / Formオブジェクトに適切に振り分けられている（Serviceクラスは不使用）
- [ ] ポリシーが整合性分類（強/結果）に基づいて実装されている
- [ ] リードモデルの構成元と実装形態が明記されている
- [ ] 外部システムが Infrastructure 層に配置されている
- [ ] BC境界が module/namespace に反映されている
- [ ] layered-rails の4層ルール（上位→下位の単方向依存）に違反していない
