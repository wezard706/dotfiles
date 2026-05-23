# RSpec 実装パターン リファレンス

---

## Executable Specification（実行可能な仕様書）

テストは「実行可能な仕様書」である。従来のドキュメントは、コードが変更されても自動更新されないため、すぐに内容が古くなる。テストを仕様書として扱うと以下のメリットがある。

- **常に最新**: テストが通っている＝その振る舞いが現在の正解であることを保証する
- **具体性**: 自然言語の曖昧さがなく、「この入力ならこの出力」という厳密な定義になる
- **信頼性**: テストを読めば仕様を理解でき、別のドキュメントを参照する必要がない

### 注意点：「振る舞い」をテストする

「内部実装（変数の状態・プライベートメソッドの呼び出し）」をテストすると、リファクタリングのたびにテストが壊れる。**「外から見た振る舞い（入力と出力・副作用）」**にフォーカスして書くこと。

```ruby
# 悪い例: 内部実装に依存している
it 'キャッシュ変数を更新すること' do
  order.calculate_total
  expect(order.instance_variable_get(:@cached_total)).to eq 1000
end

# 良い例: 外から見た振る舞いをテストする
it '合計金額を返すこと' do
  expect(order.calculate_total).to eq 1000
end
```

---

## Arrange-Act-Assert（AAA）パターン

テストは Arrange（前提準備）→ Act（実行）→ Assert（検証）の3要素で構成する。ただし **Arrange は原則 `it` の外に出す**（`let!`/`let`/`before`）。`it` のボディに残すのは Act と Assert だけにすると、各テストが「何を実行して何を期待するか」に絞られ、context ごとの前提の差分も `let`/`before` 側で見比べられる。

| ブロック | 置き場所 |
|---------|------|
| Arrange | `let!`/`let`/`before`（`it` の外）。使い分けは後述の「let / let! / before の使い分け」 |
| Act     | `it` のボディ |
| Assert  | `it` のボディ |

**Act と Assert の間は1行空ける**。「実行」と「検証」の境界が視覚的に分かれ、テストの構造が読み取りやすくなる。

```ruby
# 良い例: Arrange は let に外出し、it は Act/Assert だけ
let!(:order) { build(:order, items:) }

it '合計金額を返すこと' do
  total = order.calculate_total         # Act

  expect(total).to eq 1000              # Assert
end

# 悪い例: Arrange を it のボディにベタ書きしている
it '合計金額を返すこと' do
  order = build(:order, items:)
  total = order.calculate_total
  expect(total).to eq 1000
end
```

`expect { ... }` の中で実行と検証を一体で書く場合（例外・状態変化の検証）は、Act と Assert が1文に収まるため空行は不要。

---

## describe / context / it の使い分け

describe/context/it の命名規約は、**設計（test-design のアウトライン）と実装で共通の正本**。両フェーズともここに従って名前を付ける。

- `describe`: テスト対象そのもの（クラス名・メソッド名）
- `context`: テスト実行時の前提条件・状態。**場合分け（入力・前提の区分）はすべて context に置く**。**「〜の場合」で終える**
- `it`: **期待結果だけ**を述べる。**「〜こと」で終える**（`true を返すこと` / `残高が1減ること`）。**前提・入力の条件を `it` に書かない**

**主語・目的語を省略しない。テスト・メソッド上の役割語で呼ばない**。「対象」「判定対象」「それ」「入力」「パラメータ」のような語は、メソッドのシグネチャを知らない読み手には何を指すか伝わらない。メソッド引数を context に持ち込むときは、その役割名ではなく **それがドメインで何を意味するか**で表す。多くは「誰が何をした」という**イベント**で書くと自然になる。

- 悪い: `判定対象が被招待者の初回モニター投稿の場合`（「判定対象」が何か不明）
- 良い: `被招待者が初めてモニター投稿した場合`（引数 `monitor_post` を投稿イベントとして表現）
- 良い: `達成済み` ではなく `リファラルが達成済み`（主語を明示）

`context` 名 + `it` 名をつなげて読むと **テスト対象の仕様を説明する自然な一文**になり、かつ読み手がメソッドのシグネチャを知らなくても理解できるのがゴール（`被招待者がコーチでない場合` → `false を返すこと`）。`it` 名に「〜の場合/〜のとき」が現れたら、それは context に移すべき条件のサイン。

```ruby
RSpec.describe Stack, type: :model do
  describe '#push' do
    context '文字列をpushした場合' do
      it '返り値がpushした値であること' do
        expect(stack.push('value')).to eq 'value'
      end
    end

    context 'nilをpushした場合' do
      it 'ArgumentErrorになること' do
        expect { stack.push(nil) }.to raise_error(ArgumentError)
      end
    end
  end
end
```

### 条件にラベルを振らない

複合条件（`a && b && c`）を網羅するときも、条件にラベルを振って名前から参照しない。`A`/`B`/`C`、`C1`/`C2`/`C3`、`条件1`、真偽組合せ（`TTT`/`FTT`、`C1=T, C2=F`）といった記号は **context/it 名にもコメントにも書かない**。読み手が凡例と名前を往復しないと意味が取れなくなるため。条件は context 名の中に**言葉そのまま**で書く（`被招待者がコーチでない場合`）。

複合条件 AND の条件網羅（`coach? && first_post? && not_achieved?`）の例。各条件を1つだけ偽にして false を確かめる。**context は前提を主語・目的語つき（引数はイベントとして）述べ、`it` は結果だけを述べる**。

```ruby
RSpec.describe Objects::ReferralAchievementPolicy do
  describe '#achievable?' do
    context '被招待者がコーチで、初めてモニター投稿し、リファラルが未達成の場合' do
      it 'true を返すこと'
    end
    context '被招待者がコーチでない場合' do
      it 'false を返すこと'
    end
    context '被招待者が2回目以降のモニター投稿をした場合' do
      it 'false を返すこと'
    end
    context 'リファラルが既に達成済みの場合' do
      it 'false を返すこと'
    end
  end
end
```

---

## let / let! / before の使い分け

- **let!**: expectation で参照するオブジェクト（テストに関係するデータ）
- **before**: 参照しない準備処理（対照データの作成など）
- **let（遅延評価）**: context ごとに値を差し替えるときのみ使う

```ruby
describe '.active' do
  let!(:active_user) { create :user, deleted: false, confirmed_at: Time.zone.now }

  before do
    create :user, deleted: true, confirmed_at: Time.zone.now   # 対照データ
    create :user, deleted: false, confirmed_at: nil            # 対照データ
  end

  it 'activeユーザーのみ返すこと' do
    expect(User.active).to eq [active_user]
  end
end
```

---

## スコープ

各 context/describe には、その配下すべての it で使うものだけを置く。共通データを外側に置かない。

```ruby
# 悪い例: context 'a' では不要なデータが存在する
describe 'sample' do
  let!(:shared) { create :post }
  context 'a' do ... end
  context 'b' do ... end
end

# 良い例: 必要なスコープに閉じる
describe 'sample' do
  context 'a' do ... end
  context 'b' do
    let!(:shared) { create :post }
    ...
  end
end
```

---

## 必要最小限のレコード作成

- DB保存が不要なら `create` でなく `build` を使う
- テストに直接関係するデータのみ作成する

```ruby
# DBアクセス不要なメソッドは build で十分
let!(:user) { build :user, first_name: 'Taro', last_name: 'Yamada' }

it 'フルネームを返すこと' do
  expect(user.fullname).to eq 'Taro Yamada'
end
```

---

## update でデータを変更しない

`before { record.update(...) }` は避け、最初から目的の状態で作成する。

```ruby
# 悪い例
before { post.update(publish_at: nil) }

# 良い例
let!(:post) { create :post, publish_at: nil }
```

---

## let の上書きを避ける

context で let を上書きするのではなく、context ごとに明示的に定義する。

```ruby
# 悪い例
let!(:post) { create :post, status: status }
let(:status) { :open }

context 'when closed' do
  let(:status) { :close }  # 上書き
end

# 良い例
context 'when closed' do
  let!(:post) { create :post, status: :close }
end
```

---

## subject の使い方

副作用を伴う処理では subject に名前をつける。

```ruby
# 悪い例
subject { client.save_records(params) }
it { expect { subject }.to change { Item.count }.by(10) }

# 良い例
subject(:save_records) { client.save_records(params) }
it { expect { save_records }.to change { Item.count }.by(10) }
```

---

## FactoryBot のデフォルト値

最も一般的なケースをデフォルト値にする。テストは必要な値のみ明示的に指定する。

```ruby
# 良い例
FactoryBot.define do
  factory :user do
    sequence(:name) { |i| "test#{i}" }
    active { true }
  end
end

# テスト側で必要な値のみ指定
let!(:user) { create :user, active: true }
```

has_many の関連はデフォルトで作成しない（trait で任意に追加する）。

---

## テストダブル（モック）の使い方

参考: [サバンナ便り〜自動テストに関する問題と解決策〜 第4回](https://gihyo.jp/dev/serial/01/savanna-letter/0004#sec1)

「モック」はスタブ・スパイ・モック・フェイクなどを総称する「テストダブル」の一種。

### 使うべき状況

| 状況 | 理由 |
|------|------|
| 再現困難な例外条件（ネットワーク障害、ディスクエラーなど） | 本物では準備が難しいシナリオを再現できる |
| 外部サービス呼び出しなど遅くて不安定な依存 | テストの速度と決定性を確保する |

### 使うべきでない状況

同一プロセス内で安定して動作するものにはテストダブルを使わない。「テストが遅いから」という理由だけでの使用も避ける。

| 状況 | 代替手段 |
|------|---------|
| DBデータが必要 | factory_bot でデータを作成する |
| 状態のセットアップ | 実際のメソッドを呼び出して状態を作る |
| 時刻に依存するロジック | `travel_to` で固定する |

### 注意点

**テストの脆弱化**: 過度なテストダブルは実装の細部をテストコードに漏らし、リファクタリングで壊れやすいテストになる。

**モックドリフト**: 依存対象が変更されても、テストダブルはそれを反映しない。本来失敗すべきテストが成功し続けるリスクがある。

**設計のサイン**: テストダブルなしでテストが書きにくい場合、それは設計の問題の兆候。`allow_any_instance_of` が必要になったら依存性注入でリファクタリングする機会。
