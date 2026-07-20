# セキュリティ レビュールーブリック

> **主経路はビルトインの `security-review` スキル**（Anthropic公式・誤検知フィルタリング内蔵）。
> Skillツールで `security-review` を起動できる場合はそちらを実行し、結果を code-review の出力形式にマッピングする。
> このファイルは (a) security-review スキルが利用できない環境のフォールバック、(b) Next.js 固有の補足チェック。

## フォールバック: 基本チェックリスト

- **インジェクション**: SQLインジェクション（文字列連結のwhere/order）、コマンドインジェクション（外部入力を含む system/バッククォート）、XSS（`html_safe` / `raw` への外部入力）
- **認証・認可**: アクション単位の権限チェック漏れ、IDOR（他人のリソースIDを指定してアクセスできる）、`current_user` スコープを通らない `Model.find`
- **機密情報**: パスワード・APIキー・トークンのハードコーディング、ログへの機密情報出力、エラーメッセージでの内部情報漏洩
- **入力バリデーション**: 外部入力（ユーザー入力・外部API応答）の検証漏れ、Strong Parametersの過剰許可（`permit!`）
- **依存ライブラリ**: 既知の脆弱性を持つバージョンの追加・据え置き
- **CSRF / セッション**: `protect_from_forgery` の無効化、`skip_before_action :verify_authenticity_token`

## Next.js 固有の補足チェック（.ts / .tsx 変更時は必ず確認）

- **`NEXT_PUBLIC_` への秘密情報混入**: `NEXT_PUBLIC_` プレフィックス付き環境変数はクライアントバンドルに埋め込まれ公開される。APIキー・シークレットが含まれていないか

```bash
git diff main...HEAD | grep -n "NEXT_PUBLIC_" | grep -iE "secret|key|token|password"
```

- **Server Actions / Route Handler の認可漏れ**: `"use server"` 関数・`app/api/` の Route Handler は公開エンドポイント。middleware やページ側のチェックに頼らず、**関数内で**認証・認可を検証しているか
- **`dangerouslySetInnerHTML`**: 外部入力・DB由来の値を渡していないか（サニタイズの有無）
- **オープンリダイレクト**: `redirect(searchParams.returnUrl)` のように外部入力をリダイレクト先に使っていないか（許可リスト検証）
- **サーバー専用モジュールの漏出**: 秘密情報を扱うモジュールに `server-only` ガードがあるか（詳細はアーキテクチャ観点と重複するため、秘密情報を含む場合のみここで指摘）
