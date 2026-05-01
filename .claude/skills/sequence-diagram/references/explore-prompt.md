# Exploreサブエージェント指示書テンプレート

シーケンス図生成のためにExploreサブエージェントへ送る指示書のテンプレート。

プレースホルダー `{{ENTRY_POINT}}`・`{{SCOPE_HINT}}` を差し替えて使う。

---

## テンプレート本文

以下のコードからシーケンス図を生成するために、呼び出しグラフを構造化して返してください。**正常系（ハッピーパス）のみ**をトレース対象とし、エラー処理・例外・rescue・バリデーション失敗・認可失敗・業務上の中断分岐は記録しません。

**エントリポイント**: {{ENTRY_POINT}}
**スコープの方向**: {{SCOPE_HINT}}  (例: "エントリポイント内部の呼び出しのみ" / "enqueue元も上流へ辿る" / "フロントエンドのボタンクリックから")

## 展開/停止ルール

以下のルールに従って、呼び出しを「展開」「参照のみ」「停止点」の3段階に分類してください。

### 展開する（内部メソッド呼び出しをすべてトレース）
- ビジネスロジック層: `services/`・`use_cases/`・`commands/`・`handlers/`・`interactors/` 配下
- エントリポイント層: Controller・GraphQL Resolver/Mutation/Subscription・DataLoader Source・Job/Worker・Event Handler
- モデルの副作用メソッド（`create!`・`update_xxx!`・複数モデル更新・トランザクション・ジョブenqueue等）

### 参照のみ（呼び出しは記録するが内部は追わない）
- Pure getter・formatter・scope・validator
- Framework/library標準機能
- 1-2行の自明なヘルパー

### 停止点（呼び出し先として記録するが、それ以上潜らない）
- DB操作（クエリ・永続化）
- 外部HTTP呼び出し
- ジョブ/キュー投入
- ネットワーク境界

判定に迷ったら「展開」側に倒す。

## 含める要素・省く要素

- 認証・認可: **省く**
- ログ・メトリクス送信: **省く**
- トランザクション境界: **記録する**（開始/終了位置）
- エラー・例外・rescue・バリデーション失敗・認可失敗・業務上の中断分岐: **省く**（正常系のみ記録する）
- 両方とも正常な並行ルート（キャッシュヒット/ミス、新規/更新の判定など、どちらも成功で終わるもの）: 記録してよい
- ジョブのenqueue: 記録し、ジョブ本体のトレースは**別のエントリポイントとして**取得

## 返却フォーマット

以下のJSONを返してください。

```json
{
  "entry_point": {
    "file": "app/graphql/mutations/create_user_mutation.rb",
    "class": "Mutations::CreateUserMutation",
    "method": "resolve",
    "line": 12
  },
  "participants": [
    {
      "id": "Mutation",
      "kind": "class",
      "name": "Mutations::CreateUserMutation",
      "file": "app/graphql/mutations/create_user_mutation.rb"
    },
    {
      "id": "Service",
      "kind": "class",
      "name": "UserRegistrationService",
      "file": "app/services/user_registration_service.rb"
    },
    {
      "id": "DB",
      "kind": "boundary",
      "name": "Database"
    },
    {
      "id": "Queue",
      "kind": "boundary",
      "name": "Job Queue"
    }
  ],
  "steps": [
    {
      "from": "Mutation",
      "to": "Service",
      "kind": "call",
      "label": "register(params)",
      "description": "ユーザー登録を実行",
      "file": "app/graphql/mutations/create_user_mutation.rb:15"
    },
    {
      "kind": "transaction_begin",
      "in": "Service",
      "file": "app/services/user_registration_service.rb:20"
    },
    {
      "from": "Service",
      "to": "DB",
      "kind": "call",
      "label": "INSERT users",
      "description": "ユーザー情報を保存",
      "file": "app/services/user_registration_service.rb:22"
    },
    {
      "from": "Service",
      "to": "Queue",
      "kind": "enqueue",
      "label": "WelcomeEmailJob",
      "description": "ウェルカムメール送信をenqueue",
      "file": "app/services/user_registration_service.rb:28"
    },
    {
      "kind": "transaction_end",
      "in": "Service",
      "file": "app/services/user_registration_service.rb:30"
    },
    {
      "from": "Service",
      "to": "Mutation",
      "kind": "return",
      "label": "User",
      "description": "登録済みユーザー"
    }
  ],
  "async_branches": [
    {
      "trigger": "WelcomeEmailJob",
      "entry_point": {
        "file": "app/jobs/welcome_email_job.rb",
        "class": "WelcomeEmailJob",
        "method": "perform"
      },
      "note": "ジョブ本体のトレースが必要な場合は別途リクエストしてください"
    }
  ],
  "alt_branches": [
    {
      "condition": "新規ユーザー",
      "then_steps": [
        { "from": "Service", "to": "DB", "kind": "call", "label": "INSERT users" }
      ],
      "else_steps": [
        { "from": "Service", "to": "DB", "kind": "call", "label": "UPDATE users" }
      ],
      "note": "両方のブランチが正常終了する分岐のみ記録（エラー分岐は記録しない）"
    }
  ],
  "omitted": [
    {
      "reason": "認証ミドルウェアは省略（ルールによる）",
      "location": "app/controllers/application_controller.rb#authenticate_user!"
    }
  ],
  "warnings": [
    "User#notify_admins は動的ディスパッチを使っており、呼び出し先を静的に特定できませんでした"
  ]
}
```

## 重要な注意点

- **ファイルパスと行番号を必ず付ける**。後でメインが図に変換する際の検証に使う
- **participant.id は短く**（図の可読性のため）。長いクラス名はエイリアスを使う
- **steps の順序はコード上の実行順序**に従う
- **正常系のみトレース**。エラー処理・例外・rescue・バリデーション失敗・認可失敗・業務上の中断分岐は steps にも alt_branches にも入れない
- **`alt_branches` は両方のブランチが正常終了する場合のみ使う**（例: 新規/更新の判定、キャッシュヒット/ミス）。エラー側を含む分岐は記録しない
- **非同期処理は必ず `async_branches` に分離**。同じJSONにジョブ本体を混ぜない
- **追跡不可な箇所は `warnings` に明記**。推測で埋めない

静的解析だけでは曖昧な箇所（動的ディスパッチ・メタプログラミング・コールバック等）は、可能な限り warnings に書いて返してください。

なお `kind` フィールドに `raise` などエラー伝搬を表す値は使用しません（正常系のみ記録するため）。
