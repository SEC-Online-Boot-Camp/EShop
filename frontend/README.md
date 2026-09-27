# EShop フロントエンド

`backend/`（FastAPI）の API を呼び出す画面です。React + TypeScript + Vite で作っています。

> このフロントエンドは `frontend` ブランチにだけあり、講座 No.1〜3 では使いません。
> クーポン機能（No3 の完全コード）を前提にしています。

## 必要なもの

- Node.js 24 以降（npm を含む）
- バックエンド（`backend/`）が起動していること

## 起動方法

ターミナルを2つ使います。

```powershell
# 1つ目: バックエンド（backend/ で。初回は python -m app.seed で初期データを投入）
cd backend
uvicorn app.main:app --reload

# 2つ目: フロントエンド
cd frontend
npm install
npm run dev
```

ブラウザで <http://localhost:5173> を開きます。初期データのユーザーは `taro@example.com` / `password123` です。
クーポンは `SPRING10`（10%引き・上限1,000円）と `FLAT500`（500円引き）などが使えます（`backend/app/seed.py` を参照）。

## 構成

| パス | 内容 |
| :--- | :--- |
| `src/api/types.ts` | API の型。`backend/app/schemas.py` と対応させている |
| `src/api/client.ts` | fetch のラッパー。エラー応答を `ApiError` にする |
| `src/auth/` | ログイン状態（JWT）の保持と、要ログイン画面のガード |
| `src/pages/` | 商品一覧・ログイン・カート（クーポン適用）・注文完了 |
| `vite.config.ts` | `/api/*` をバックエンド（`127.0.0.1:8000`）へ転送するプロキシ |

画面からは `/api/cart` のように呼び、Vite が `/api` を外して `http://127.0.0.1:8000/cart` へ転送します。
ブラウザからは同じオリジンに見えるので、バックエンドに CORS の設定は要りません。

## テストなど

```powershell
npm test        # Vitest（API クライアント・カート画面）
npm run lint    # oxlint
npm run build   # 型チェック + 本番用ビルド（dist/）
```

## 既知の割り切り

- **JWT は `localStorage` に保存している。** XSS があるとスクリプトから読み出せる保存先で、研修用の簡易実装。
- **API の型は手書き。** OpenAPI（`/openapi.json`）からの自動生成（`openapi-typescript` 等）は、
  2026-09 時点で TypeScript 6 に対応した版がないため見送った。`schemas.py` を変えたら `types.ts` も直すこと。
- **カートの数量変更・削除、注文履歴の画面はない。** 対応する API がないため。
