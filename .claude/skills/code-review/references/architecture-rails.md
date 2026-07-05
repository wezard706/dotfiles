# アーキテクチャ（Rails レイヤード設計）レビュールーブリック

> このファイルは layered-rails プラグイン（`layered-rails:layered-rails-reviewer` エージェント）が
> 利用できない環境でのフォールバック。プラグインが利用可能な場合はそちらを優先する。

## 問い

「presentation → application → domain」の層構造に対する逆方向依存はないか。
Modelの肥大化よりも逆方向依存の方がテスタビリティとリファクタ容易性を毀損する。

## Critical（レイヤー境界違反 — マージ前必修正）

- Modelが `Current.user` / `Current.account` 等のpresentation層の文脈に依存していないか（バックグラウンドジョブで壊れる）
- Serviceがrequest / paramsオブジェクトを受け取っていないか（presentation層の関心事の漏れ込み）
- Controllerにビジネス計算ロジック（金額計算・割引適用など）が埋め込まれていないか
- Viewが単純なassociation参照を超えてDBクエリを発行していないか
- Mailer・Notification・外部APIへの副作用がModelのcallback（after_commit等）から直接起動されていないか

### 検出手順

```bash
# 変更されたモデル内の Current 参照
git diff main...HEAD -- app/models | grep -n "Current\."
# モデルのコールバックからの副作用
git diff main...HEAD -- app/models | grep -nE "after_(commit|save|create|update).*(Mailer|Notification|Job|deliver)"
```

### 例

```ruby
# 悪い例: Modelがpresentation文脈に依存
def complete!
  self.completed_by = Current.user  # バックグラウンドジョブではnil
  save!
end

# 良い例: 明示的なパラメータで受け取る
def complete!(by:)
  self.completed_by = by
  save!
end
```

## Warning（修正または明示的合意が必要）

- 新規コールバックが5段階スコアで4点以上か
  - Transformer（値の計算）5点 / Normalizer（入力の正規化）4点 / Utility（カウンタキャッシュ）4点 → 維持
  - Observer（副作用）2点 → 要レビュー / Operation（業務プロセスの一手順）1点 → 抽出推奨
- `skip_*` / `unless: :flag` などの制御フラグでコールバックを抑制していないか
- Concernが振る舞いベースで単独テスト可能か（`Validations`・`Scopes` のような成果物タイプでのcode-slicingは避ける）
- Concernが50行を超えて肥大化していないか
- ドメインロジックがServiceへ流出してModelが貧血化していないか
- Serviceが単なる薄いラッパー（モデルメソッドを呼ぶだけ）になっていないか
- 高頻度変更 × 高複雑度のGod Object兆候はないか

## 層違反の解消手順

1. 呼び出し連鎖をトレースする（Controller/Job → Service → Model のどこで違反しているか）
2. 既存のオーケストレーター（Service・Form・Controller）を探す
3. あれば副作用をそこへ移動、なければ選択肢（Controller / Service / Form）を提示してユーザーに委ねる
