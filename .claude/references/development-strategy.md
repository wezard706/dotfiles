# 開発戦略ガイドライン

## 基本原則

- **変更容易性（ETC原則）**が最も重要。将来の変更コストを常に意識して設計する
- **戦略的プログラミング**（A Philosophy of Software Design）: 動けばいいという戦術的思考を避け、良い設計に投資する

## ドメインモデリング（増田亨流DDD）

- 業務の言葉をそのままコードに落とし込む
- namespace, class, module, method, 変数の名前で「仕様を語る」。技術用語より業務用語を優先する
- ロジックはドメインモデル（ActiveRecord または PORO）に寄せる。モデルを薄くしない

## 命名

命名の目的は、読み手の**認知的負荷を最小化**すること。コードを見た瞬間に、その変数が何を持ち、何のために存在するかを直感的に理解できる状態を目指す。

### 「何（What/How）」より「なぜ（Why/Purpose）」

実装の仕方ではなく、その存在の意図・役割を名前に込める。

```ruby
# ❌ 処理の手段を説明している
def send_email_via_smtp(user)

# ✅ ビジネス上の意図を表現している
def notify_payment_failure(user)
```

### ビジネスの言葉をそのまま使う

エンジニアだけが理解できる技術用語ではなく、ビジネスサイドと共通の言葉をクラス名・変数名に使う。

```ruby
# ❌ 技術的な視点の命名
class UserStatusUpdater
  def run(user_id, status_code)

# ✅ ビジネス用語で語る命名
class MembershipSuspension
  def execute(member)
```

### 情報の密度を重視する

名前だけでそのオブジェクトの役割が正確にイメージできる明確さを追求する。

```ruby
# ❌ 情報が薄い
data, result, temp, info, obj

# ✅ 役割が一意に定まる
invoice_line_items
payment_gateway_response
retry_interval_seconds
```

## 設計上の優先順位

- **継承より集約**を圧倒的に好む
- **サービスオブジェクトの安易な作成を避ける**。以下の場合のみ許容する:
  - 複数の集約にまたがる操作でどのモデルにも自然に属さない場合
  - 外部サービスとのコア業務連携
