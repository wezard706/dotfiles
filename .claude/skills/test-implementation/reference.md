# RSpec 実装パターン リファレンス

参考: [willnet/rspec-style-guide](https://github.com/willnet/rspec-style-guide)

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

各テストケースを3つのブロックに分けて記述する。

| ブロック | 内容 |
|---------|------|
| Arrange | 前提条件のセットアップ（DBデータ、オブジェクトの状態など） |
| Act     | テスト対象メソッドの実行 |
| Assert  | 戻り値・副作用の検証 |

---

## describe / context の使い分け

- `describe`: テスト対象そのもの（クラス名・メソッド名）
- `context`: テスト実行時の前提条件・状態（`〜の場合` で記述）
- `it`: 期待結果（`〜すること` で記述）

```ruby
RSpec.describe Stack, type: :model do
  describe '#push' do
    context '文字列をpushしたとき' do
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

固定値ではなくランダム値をデフォルトにする。テストは必要な値のみ明示的に指定する。

```ruby
# 良い例
FactoryBot.define do
  factory :user do
    sequence(:name) { |i| "test#{i}" }
    active { [true, false].sample }
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
