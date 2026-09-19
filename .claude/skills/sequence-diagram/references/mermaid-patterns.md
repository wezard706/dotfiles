# Mermaid シーケンス図 記法リファレンス

シーケンス図生成でよく使う記法パターン集。実装で迷ったらここを参照。

> **注意**: このスキルは正常系（ハッピーパス）のみを描く。エラー処理・例外・失敗分岐を表現する記法（`->x`/`-->x` のエラー矢印、`critical` ブロック等）は使わない。`alt`・`opt` も両方とも正常終了する分岐に限って使う。

---

## 基本形

```mermaid
sequenceDiagram
    participant A
    participant B
    A->>B: リクエスト
    B-->>A: レスポンス
```

- `->>`: 実線矢印（同期呼び出し）
- `-->>`: 点線矢印（レスポンス・非同期）
- `participant X as Y`: エイリアス（X が短縮名、Y が表示名）

---

## エイリアス（長いクラス名を短縮）

```mermaid
sequenceDiagram
    participant Ctrl as UsersController
    participant Svc as UserRegistrationService
    Ctrl->>Svc: register(params)
```

クラス単位モードではクラス名が長くなりやすいため、エイリアスを積極的に使う。

---

## トランザクション境界（rect で囲む）

```mermaid
sequenceDiagram
    participant Svc as UserService
    participant DB

    rect rgb(240, 240, 220)
    Note over Svc,DB: トランザクション開始
    Svc->>DB: INSERT users
    Svc->>DB: INSERT user_profiles
    Note over Svc,DB: トランザクション終了
    end
```

- `rect rgb(...)` で背景色を付けた範囲を作る
- `Note over X,Y: ...` で範囲の意味を明示

---

## 条件分岐（alt / else）

```mermaid
sequenceDiagram
    participant Svc
    participant DB
    Svc->>DB: SELECT user by email
    alt 既存ユーザー
        DB-->>Svc: user
        Svc->>DB: UPDATE last_login_at
    else 新規ユーザー
        DB-->>Svc: nil
        Svc->>DB: INSERT users
    end
```

- **両方のブランチが正常終了する分岐のみ**使う（例: 新規/更新の判定、初回/2回目以降）
- エラー・例外・失敗を伴う分岐には使わない（正常系のみ描く方針）
- 分岐が多いとすぐに読めなくなるので厳選

---

## ループ（loop）

```mermaid
sequenceDiagram
    participant Svc
    participant API
    loop 各アイテムごと
        Svc->>API: POST /items
        API-->>Svc: 200 OK
    end
```

N+1 的な繰り返しや、配列処理を表現するとき。

---

## 並列処理（par）

```mermaid
sequenceDiagram
    participant Svc
    participant A as APIサービスA
    participant B as APIサービスB
    par 並列呼び出し
        Svc->>A: リクエスト
    and
        Svc->>B: リクエスト
    end
```

`Promise.all`・`Parallel.each`・`Concurrent::Promises` 等を表現。

---

## オプショナル（opt）

```mermaid
sequenceDiagram
    participant Svc
    participant Cache
    participant DB
    Svc->>Cache: GET user
    opt キャッシュミス時
        Svc->>DB: SELECT user
        Svc->>Cache: SET user
    end
```

「ある条件下のみ実行」を表現。`alt` の片側だけ必要なときに使う。

---

## 非同期ジョブのenqueueとジョブ本体（同じ図に続けて描く）

```mermaid
sequenceDiagram
    participant Ctrl as UsersController
    participant Svc as UserService
    participant DB
    participant Queue as Job Queue
    participant Job as WelcomeEmailJob
    participant Mailer as UserMailer

    Ctrl->>Svc: register(params)
    Svc->>DB: INSERT users
    Svc--)Queue: WelcomeEmailJob をenqueue
    Note over Svc,Queue: 非同期境界（ここから先はジョブワーカー側で実行）
    Svc-->>Ctrl: User
    Queue--)Job: perform(user_id)
    Job->>Mailer: welcome_email(user).deliver_now
```

- `--)` は非同期を示す矢印（点線・open arrow）
- `Note over ...` で非同期境界を明示し、それ以降がワーカー側の処理であることを示す
- ジョブ本体（`perform`内部）は**同じ`sequenceDiagram`ブロック内の続き**として描く（別図には分けない）。Controller への return とジョブ実行はどちらも非同期境界の後ろに並べてよい
- 1リクエストで複数のジョブをenqueueする場合は、それぞれの enqueue → perform を順番に並べる

---

## アクティベーション（オプション・使うと読みやすい場合のみ）

```mermaid
sequenceDiagram
    participant A
    participant B
    A->>+B: 呼び出し
    B->>+A: コールバック
    A-->>-B: 応答
    B-->>-A: 完了
```

- `->>+` で activate、`-->>-` で deactivate
- ネストした呼び出しや長い処理を視覚化するのに便利
- 使わなくても正しく読めるので、複雑なときのみ追加

---

## Note（補足）

```mermaid
sequenceDiagram
    participant A
    participant B
    A->>B: リクエスト
    Note right of B: DBに保存<br/>副作用あり
    B-->>A: 完了
    Note over A,B: 動的ディスパッチのため<br/>実際のクラスは実行時決定
```

- `Note left of X`・`Note right of X`・`Note over X,Y`
- `<br/>` で改行
- 動的ディスパッチ・推測部分・前提条件などを補足

---

## Self-call（自己呼び出し）

```mermaid
sequenceDiagram
    participant Svc
    Svc->>Svc: validate!
    Svc->>Svc: normalize_params
```

同一クラス内のメソッド呼び出し。展開ルール上で業務ロジックを含むなら記載する。

---

## 使い分けのコツ

- **最初は基本形だけで描いてみる**。読めなかったら `alt`・`loop`・`rect` を足していく
- **アクティベーション（`+`/`-`）は複雑さが増すので、読みやすさが勝るときのみ使う**
- **Note は多用しない**。図本体で意味が通るのが理想。Noteは「描けない事情」を補足する用途
- **色付き rect はトランザクション専用** にしておくと一貫性が出る（他用途に使わない）
