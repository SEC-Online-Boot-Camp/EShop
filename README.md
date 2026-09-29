# EShop（coupon ブランチ：No.3 試験・品質管理版）

AI活用入門講座（SW編）で使用する、既存ECサイトを模したFastAPIアプリケーションです。

> **このブランチ（`coupon`）は、クーポン/割引適用機能を実装済みの状態です。**
> No.1・No.2で使う開始状態（クーポン機能なし）は `main` ブランチにあります。
> No.1・No.2で使ってきたフォルダのまま、次のように切り替えます。
>
> ```powershell
> git fetch origin
> git switch coupon
> ```
>
> `docs/`に保存した成果物や`.env`への変更はそのまま残ります。

No.3では実装作業は行いません。この実装に対して**試験観点を洗い出し、テストコードを書き、
見つかった不具合をデバッグする**のが課題です。

> **注意**：このクーポン機能は**コードレビューとテストが未完了**です。動作は保証されません。
> 「実装済み＝正しく動く」ではありません。設計書（クーポンAPI設計書）と突き合わせて、
> 期待どおりに動くかを自分のテストで確かめてください。

> **No.4（認定課題）もこの`coupon`ブランチのまま使います。** ブランチの切り替えも
> データベースの作り直しも行いません。

## 構成

| パス | 内容 |
| :--- | :--- |
| `backend/` | FastAPI のバックエンド（API・テスト） |
| `frontend/` | React + TypeScript + Vite の画面（クーポンの適用・解除を含む）。詳細は [frontend/README.md](frontend/README.md) |
| `.vscode/` | VS Code のテストパネルで、backend の pytest を `backend/` から動かす設定 |

CI と Claude による PR レビュー（`.github/`）は講座では使わないため、`github-config` ブランチに残しています。

## セットアップ

No.1で作った仮想環境をそのまま使います。作り直しやインストールのやり直しは不要です。
データベースだけは作り直してください（`backend/` で実行）。

```powershell
cd backend
.venv\Scripts\activate
Remove-Item ecommerce.db -ErrorAction SilentlyContinue
python -m app.seed
pytest
```

`ecommerce.db`の削除は必須です。クーポン機能では`orders`テーブルに`coupon_code`・
`discount_amount`の2列が増えますが、`seed`が使う`create_all()`は既存テーブルに列を追加しません。
No.1で作ったDBをそのまま使うと、注文確定で`table orders has no column named coupon_code`という
エラーになります。DBの中身はすべて`seed`で作り直せます。

`python -m app.seed`はユーザー2件・商品5件・クーポン6件を投入します。
`pytest` は既存テスト55件がすべてPASSします。これが**回帰試験の基準線**です。
No.3で追加するテストを含めて全件PASSするところまで持っていくのが最終ゴールになります。

バックエンドの依存は `backend/pyproject.toml` と `backend/uv.lock` で固定しています。[uv](https://docs.astral.sh/uv/) を使う場合は、`backend/` で次を実行すると、`backend/.venv` に同じ環境ができます（pip を使う場合は、同じ版の `backend/requirements.txt` を使います）。

```powershell
cd backend
uv sync
```

画面も使う場合は、バックエンドを起動したうえで別のターミナルで次を実行し、<http://localhost:5173> を開きます
（Node.js 24 以降が必要）。

```powershell
cd frontend
npm install
npm run dev
```

カバレッジを確認したい場合は、`backend/` で以下を実行する。

```bash
pytest --cov=app --cov-report=term-missing
```

HTML形式のレポートも生成できる（`htmlcov/index.html` をブラウザで開く）。

```bash
pytest --cov=app --cov-report=html
```

既存テストがどこまで保証していてどこからが未検証か（ミューテーションテストの結果を含む）は [backend/TESTING.md](backend/TESTING.md) を参照。

> TESTING.mdに載っているカバレッジ・ミューテーションテストの数値は、いずれも**クーポン機能を追加する前**の
> 既存コードに対する実測値です。クーポン機能のテストは1件も入っていません。
> TESTING.mdが言う「未検証の外側」がクーポン部分そのものであり、そこを埋めるのがNo.3の課題です。

## API一覧

| メソッド | エンドポイント | 概要                                     | 認証 |
| :------- | :------------- | :--------------------------------------- | :--- |
| GET      | /              | ヘルスチェック                           | 不要 |
| POST     | /auth/login    | ログイン（JWT取得）                      | 不要 |
| GET      | /products      | 商品一覧取得                             | 不要 |
| POST     | /cart/items    | カートに商品追加                         | 要   |
| GET      | /cart          | カート内容・小計・割引後金額取得         | 要   |
| POST     | /cart/coupon   | クーポン適用（プレビュー。消費はしない） | 要   |
| DELETE   | /cart/coupon   | 適用中のクーポンを取り消す               | 要   |
| POST     | /orders        | 注文確定（クーポンの再検証・消費を含む） | 要   |

## クーポン機能の実装内容

`backend/app/coupon.py` に適用可否の判定と割引額の計算をまとめ、`backend/app/routers/cart.py`（プレビュー）と
`backend/app/routers/orders.py`（確定）の双方から呼び出しています。

| 仕様                   | 実装場所                                           |
| :--------------------- | :------------------------------------------------- |
| 定率引き／定額引き     | `backend/app/coupon.py` `calc_discount()`          |
| 割引の計算対象金額     | `backend/app/coupon.py` `calc_eligible_subtotal()` |
| 有効期限・発行数上限   | `backend/app/coupon.py` `evaluate()`               |
| 発行数の消費（原子的） | `backend/app/coupon.py` `consume()`                |
| プレビュー             | `backend/app/routers/cart.py` `apply_coupon()`     |
| 確定時の再検証・消費   | `backend/app/routers/orders.py` `checkout()`       |

### 投入済みのクーポン（`python -m app.seed`）

| コード    | 種別       | 値      | 割引上限 | 最低購入金額 | 対象外カテゴリ | 発行数上限  | 状態     |
| :-------- | :--------- | :------ | :------- | :----------- | :------------- | :---------- | :------- |
| SPRING10  | percentage | 10%     | 1,000円  | 3,000円      | なし           | 100         | 有効     |
| FLAT500   | fixed      | 500円   | —        | 3,000円      | なし           | 100         | 有効     |
| WELCOME5  | percentage | 5%      | —        | 0円          | なし           | **なし**    | 有効     |
| NOACC15   | percentage | 15%     | —        | 3,000円      | accessories    | 100         | 有効     |
| SOLDOUT   | fixed      | 1,000円 | —        | 0円          | なし           | 1（消化済） | 上限到達 |
| EXPIRED20 | percentage | 20%     | —        | 0円          | なし           | 100         | 期限切れ |

## テストで使えるフィクスチャ

`backend/tests/conftest.py` に、クーポンのテストで使うフィクスチャを用意しています。

| フィクスチャ                             | 内容                                                       |
| :--------------------------------------- | :--------------------------------------------------------- |
| `client` / `auth_headers` / `db_session` | 既存。APIクライアント・認証ヘッダ・DBセッション            |
| `sample_product`                         | 既存。単価1,000円・`is_sale=False` の商品                  |
| `cart_with_items`                        | `sample_product` を4点入れた小計4,000円のカート            |
| `sale_product`                           | 単価2,000円・`is_sale=True` の商品                         |
| `sample_coupon`                          | SPRING10相当（定率10%・上限1,000円・最低購入3,000円）      |
| `fixed_coupon`                           | FLAT500相当（定額500円・最低購入3,000円）                  |
| `unlimited_coupon`                       | WELCOME5相当（定率5%・発行数上限なし）                     |
| `exhausted_coupon`                       | SOLDOUT相当（発行数上限に到達済み）                        |
| `expired_coupon`                         | EXPIRED20相当（有効期限切れ）                              |
| `make_product` / `make_coupon`           | 任意の商品・クーポンを作るファクトリ（境界値の作り込み用） |

`make_coupon` / `make_product` は境界値テストのデータを自分で組み立てるためのものです。
既製のフィクスチャで足りない条件（端数が出る金額など）は、これらで作ってください。

## セキュリティ演習について（No.1）

`backend/.env` には、研修用にあえて用意した**架空の**機密情報（DB接続文字列・JWT秘密鍵・決済ゲートウェイAPIキー）が
含まれています。実在するシステムの値ではありませんが、「このままAIに貼り付けてよいか」を考える教材として
使ってください。本来この種のファイルはリポジトリにコミットすべきではない、という点自体も演習の対象です。
