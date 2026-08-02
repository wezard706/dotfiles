# アーキテクチャ — フロントエンド（Next.js App Router）

## 対象範囲

Server Component / Client Component の境界設計。データ取得・状態・秘密情報の層配置。前提: App Router（Next.js 13+）。バックエンドとの連携方式（REST/GraphQL）には依存しない観点のみを扱う。

## チェックリスト

### Critical（マージ前必修正）

- **サーバー専用コードのClient Component流入**: DB接続・ORM・秘密情報（環境変数）を参照するモジュールが `"use client"` ファイルからimportされていないか。`server-only` パッケージによるガードの欠如
- **`"use client"` 境界の誤配置**: インタラクションを持たない、あるいは末端の小さな部分だけがインタラクティブなコンポーネントツリーの上部に `"use client"` を置き、配下全体をクライアントバンドルに巻き込んでいないか
- **データ取得のクライアント側実装**: Server Componentで取得できるデータを `useEffect` + `fetch` で取得していないか（初期表示の遅延・ウォーターフォール・エラーハンドリング複雑化）
- **APIアクセス層の不在**: fetchロジック（エンドポイント・ヘッダー・エラー処理）がコンポーネントに直書きで散乱していないか。`lib/api/` 等の関数として分離されているか

#### 例

```tsx
// 悪い例: ページ全体をClient Component化
"use client";
export default function ProductPage() {
  const [products, setProducts] = useState([]);
  useEffect(() => { fetch("/api/products").then(...) }, []);  // クライアントフェッチ
  return <div>{products.map(...)}<LikeButton /></div>;
}

// 良い例: Server Componentで取得し、インタラクティブな末端のみClient化
export default async function ProductPage() {
  const products = await getProducts();  // lib/api/products.ts に分離
  return <div>{products.map(p => <ProductCard key={p.id} product={p} />)}</div>;
}
// LikeButton.tsx のみ "use client"
```

### Warning（修正または明示的合意が必要）

- **シリアライズ不能なpropsの受け渡し**: Server → Client Componentのpropsに関数・Date・クラスインスタンスを渡していないか（プレーンオブジェクトのみ渡せる）
- **サーバー状態の二重管理**: サーバーから取得したデータを `useState` にコピーして手動同期していないか。クライアント側で再取得・キャッシュが必要なら React Query / SWR 等の使用を検討
- **ルートセグメント構成**: ページ固有のコンポーネント・ロジックがルートセグメント内にcolocationされているか。共有コンポーネントとページ固有コンポーネントの区別
- **環境変数の層違反**: サーバーでしか使わない値に `NEXT_PUBLIC_` を付けていないか（バンドルに埋め込まれ公開される）。逆にクライアントで必要な値に付け忘れて undefined になっていないか
- **Route Handler / Server Actions の責務**: ビジネスロジックがRoute Handler内に直書きされていないか（バックエンドAPIへの委譲、または関数への分離）

### Suggestion（検討推奨）

- `loading.tsx` / `error.tsx` / Suspense境界の欠如（データ取得を伴う新規ルートの場合）
- 型定義の重複: APIレスポンス型がコンポーネントごとに再定義されていないか（共有の型定義への集約）
