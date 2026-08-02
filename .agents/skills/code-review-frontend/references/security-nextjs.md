# セキュリティ — フロントエンド（Next.js 固有の補足）

## 対象範囲

`security-review` の一般的なチェックでは拾いにくい、Next.js 固有の観点。

## チェックリスト

- **`NEXT_PUBLIC_` への秘密情報混入**: `NEXT_PUBLIC_` プレフィックス付き環境変数はクライアントバンドルに埋め込まれ公開される。APIキー・シークレットが含まれていないか
- **Server Actions / Route Handler の認可漏れ**: `"use server"` 関数・`app/api/` の Route Handler は公開エンドポイント。middleware やページ側のチェックに頼らず、**関数内で**認証・認可を検証しているか
- **`dangerouslySetInnerHTML`**: 外部入力・DB由来の値を渡していないか（サニタイズの有無）
- **オープンリダイレクト**: `redirect(searchParams.returnUrl)` のように外部入力をリダイレクト先に使っていないか（許可リスト検証）
- **サーバー専用モジュールの漏出**: 秘密情報を扱うモジュールに `server-only` ガードがあるか（詳細はアーキテクチャ観点と重複するため、秘密情報を含む場合のみここで指摘）
