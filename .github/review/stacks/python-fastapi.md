---
layer: stack
target: python-fastapi
---

# Python + FastAPI スタックのレビュー観点

> 凡例（重要度 Must/Should/Nit の定義、ISO/IEC 25010 の8品質特性一覧）は [../README.md](../README.md) を参照してください。

**Python + FastAPI + Pydantic v2 + SQLAlchemy 2（同期セッション）+ python-jose の JWT（Bearer）+ pytest**（`backend/`）を前提とした、スタック固有の観点です。
汎用観点（common / phases）では拾いきれない具体（Pydantic の制約・`Depends`・セッションとトランザクション・金額の型・pytest のフィクスチャ）に徹します。

> **層間の線引き**:
>
> - common.md の「認証・認可の欠落」や `03-basic-design.md` の「トークン方式の設計」とは重複させない（この合成では対象外・言及不要）。
>   ここでは**FastAPI での具体的な実装**（`Depends(get_current_user)`、`jwt.decode` の引数など）に絞る。
> - `05-implementation.md` の「計算・丸めが仕様どおりか」「N+1」に対し、ここでは**Python・SQLAlchemy で間違えやすい具体**（`float` の誤差、遅延読み込み）を扱う。
> - 画面でのトークンの保存先・401 の扱いは `stacks/typescript-react.md` の担当（この合成では対象外・言及不要）。

---

## 1. 入力検証（Pydantic）

### 1.1 リクエストスキーマの制約

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 機能適合性 > 機能正確性 ／ セキュリティ > 完全性
- **確認内容**:
  - 外部入力はルーター関数の引数に Pydantic モデルで受け、`dict` や `Request.json()` のまま扱っていないか確認する。
  - 数量・金額・率などに `Field(ge=..., le=...)` で範囲を付けているか確認する（既存の `CartItemCreate.quantity` は `ge=1`）。文字列に長さの上限（`max_length`）があるか確認する。
  - 区分値（配送方法など）を `str` のままにせず、`Literal` や `Enum` で受ける値を限定しているか確認する。
  - 検証エラーは FastAPI が自動で `422` を返すので、ルーター内で同じ検証を手書きして別のステータスを返していないか確認する。
- **悪い例**:
  ```python
  class ReviewCreate(BaseModel):
      rating: int        # 0 や 100 が通る
      title: str         # 空文字や 10 万文字が通る
      shipping: str      # 決めていない配送方法の文字列が通る
  ```
- **良い例**:
  ```python
  class ReviewCreate(BaseModel):
      rating: int = Field(ge=1, le=5)
      title: str = Field(min_length=1, max_length=50)
      shipping: Literal["standard", "express"]
  ```

### 1.2 レスポンスモデルで返す項目を絞る

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 機密性 ／ 互換性 > 相互運用性
- **確認内容**:
  - エンドポイントに `response_model`（または戻り値の型注釈）を付け、ORM オブジェクトをそのまま返していないか確認する。
  - 応答用のスキーマ（`...Out`）に、`hashed_password`・内部の管理用の項目・他の会員の情報が入っていないか確認する。
  - ORM から変換するスキーマに `model_config = ConfigDict(from_attributes=True)` が付いているか確認する。
- **悪い例**:
  ```python
  @router.get("/me")
  def me(user: User = Depends(get_current_user)):
      return user  # 応答の形が決まっておらず、hashed_password も含まれうる
  ```
- **良い例**:
  ```python
  @router.get("/me", response_model=UserOut)  # UserOut は id・email・member_rank だけ
  def me(user: User = Depends(get_current_user)):
      return user
  ```

---

## 2. 認証（`Depends`）と JWT

### 2.1 保護するエンドポイントへの `Depends(get_current_user)`

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 真正性 / 機密性
- **確認内容**:
  - 要ログインのエンドポイントの引数に `current_user: User = Depends(get_current_user)` があるか確認する（付け忘れると誰でも呼べる）。
  - 操作の対象となる会員を、リクエストのボディ・クエリの `user_id` ではなく `current_user.id` から決めているか確認する。
  - 管理者だけの操作は、`get_current_user` の上に権限を確かめる依存（`require_admin` など）を重ねているか確認する。
- **悪い例**:
  ```python
  @router.post("/products/{product_id}/reviews")
  def post_review(product_id: int, payload: ReviewCreate, db: Session = Depends(get_db)):
      review = Review(user_id=payload.user_id, product_id=product_id, ...)  # 他人になりすまして投稿できる
  ```
- **良い例**:
  ```python
  @router.post("/products/{product_id}/reviews", status_code=status.HTTP_201_CREATED)
  def post_review(
      product_id: int,
      payload: ReviewCreate,
      db: Session = Depends(get_db),
      current_user: User = Depends(get_current_user),
  ):
      review = Review(user_id=current_user.id, product_id=product_id, ...)
  ```

### 2.2 JWT の署名アルゴリズム・有効期限・鍵

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 真正性 / 完全性
- **確認内容**:
  - `jwt.decode` に `algorithms=[...]` を明示し、許可するアルゴリズムを固定しているか確認する（`none` や想定外の方式を受け入れない）。
  - 署名を検証せずにクレームを読んでいないか（`jwt.get_unverified_claims` や `options={"verify_signature": False}`）確認する。
  - トークンに `exp` を入れ、`verify_exp` を無効にしていないか確認する。有効期間（`JWT_EXPIRE_MINUTES`）が過度に長くなっていないか確認する。
  - 署名鍵（`JWT_SECRET_KEY`）が環境変数から供給され、未設定のときに安全でない既定値で起動していないか確認する。
- **悪い例**:
  ```python
  payload = jwt.get_unverified_claims(token)  # 署名を検証していない
  ```
- **良い例**:
  ```python
  payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])  # exp も既定で検証される
  ```

---

## 3. DB（SQLAlchemy）

### 3.1 セッションとトランザクションの境界

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 成熟性 / 回復性 ／ 機能適合性 > 機能正確性
- **確認内容**:
  - セッションは `Depends(get_db)` で受け取り、モジュールのグローバル変数でセッションを持ち回っていないか確認する。
  - 1つの操作（注文の作成・カートの削除・在庫の引当）を1つのトランザクションにまとめ、`commit()` を最後に1回だけ行っているか確認する（途中で `commit()` すると、後の失敗で部分的な更新が残る）。
  - 例外が起きたときにコミットされない（`get_db` の `close()` で破棄される）流れになっているか、途中で例外を握りつぶして `commit()` していないか確認する。
- **悪い例**:
  ```python
  db.add(order)
  db.commit()                    # ここで注文が確定する
  reserve_stock(db, cart_items)  # ここで失敗すると、在庫を引き当てていない注文だけが残る
  db.commit()
  ```
- **良い例**:
  ```python
  db.add(order)
  db.flush()                     # order.id を得るだけで、まだ確定しない
  if not reserve_stock(db, cart_items):
      raise HTTPException(status_code=409, detail="在庫が足りません")
  db.commit()                    # すべて成功したときだけ確定する
  ```

### 3.2 同時実行での check-then-update

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 成熟性 ／ 機能適合性 > 機能正確性
- **確認内容**:
  - 「読み出して Python で判定し、別の文で更新する」形で、在庫・残高などの制約を守ろうとしていないか確認する（同時に来たリクエストが両方とも判定を通る）。
  - 条件付きの `UPDATE ... WHERE stock >= :quantity` と更新件数の確認、または `with_for_update()` による行ロックで守っているか確認する。
  - 生の SQL を使う場合は `text()` とバインド変数を使っているか確認する（common.md 1.2）。
- **悪い例**:
  ```python
  if product.stock >= quantity:
      product.stock -= quantity  # 2つのリクエストが同時に通ると在庫が負になる
  ```
- **良い例**:
  ```python
  result = db.execute(
      update(Product)
      .where(Product.id == product.id, Product.stock >= quantity)
      .values(stock=Product.stock - quantity)
  )
  if result.rowcount != 1:
      raise HTTPException(status_code=409, detail="在庫が足りません")
  ```

### 3.3 遅延読み込みによる N+1

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 性能効率性 > 時間効率性
- **確認内容**:
  - `relationship` の属性（`item.product` など）をループの中で読み、明細の数だけ SELECT が飛んでいないか確認する。
  - 一覧・明細を返す箇所で `selectinload()`／`joinedload()` を使って関連をまとめて読んでいるか確認する。
- **悪い例**:
  ```python
  items = db.query(CartItem).filter(CartItem.user_id == user.id).all()
  subtotal = sum(i.product.price * i.quantity for i in items)  # 明細ごとに products を SELECT
  ```
- **良い例**:
  ```python
  items = (
      db.query(CartItem)
      .options(selectinload(CartItem.product))
      .filter(CartItem.user_id == user.id)
      .all()
  )
  ```

---

## 4. 金額の扱い

### 4.1 金額を int で扱い、端数の扱いを明示する

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 機能適合性 > 機能正確性
- **確認内容**:
  - 金額（円）は `int` で扱い、途中で `float` を経由していないか確認する（`/` の結果は `float` になり、誤差が出る）。整数で割るなら `//` や `divmod()`、率を掛けるなら整数演算か `Decimal` で行っているか確認する。
  - 端数の扱い（切り捨て・切り上げ・四捨五入、端数をどこに寄せるか）が仕様書・設計書の定義と一致しているか確認する。組み込み関数や演算の丸め方が、仕様の丸め方と同じとは限らない点に注意する。
  - 計算結果が負にならない、分けた金額を足すと元の金額に戻る、など仕様で決めた制約を守っているか確認する。
  - 金額をクライアントから受け取らず、サーバー側で商品の価格から計算し直しているか確認する。
- **悪い例**:
  ```python
  monthly = total / 3  # float になり、3 回分を足しても total に戻らない
  ```
- **良い例**:
  ```python
  base, rest = divmod(total, 3)
  payments = [base + rest, base, base]  # 端数は初回に寄せる（仕様書で決めた寄せ方）
  ```

---

## 5. エラー応答（HTTPException）

### 5.1 ステータスコードの使い分け

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 互換性 > 相互運用性 ／ 使用性 > ユーザーエラー防止性
- **確認内容**:
  - `HTTPException` のステータスが、設計書で定めた使い分けと一致しているか確認する。設計書にない場合の目安: 未ログイン・トークン不正は `401`（`WWW-Authenticate: Bearer` を付ける）、権限なしは `403`、対象がない（他人の注文を含む）は `404`、状態の衝突で受け付けないもの（在庫切れなど）は `409`、業務ルール上受け付けられない入力は `422`、前提を満たさない要求（空のカート）は `400`。
  - エラーにするか・受け付けて処理するか（上書き・無視を含む）は仕様上の判断なので、目安と違うことだけを理由に不具合と断定しない。
  - 同じ状況に対して、既存の API と同じステータスを返しているか確認する。
  - ステータスは `status.HTTP_404_NOT_FOUND` のような定数で書き、`detail` は利用者に見せてよい日本語の文言にしているか確認する（例外の内容や SQL を入れない）。なお Starlette 1.x では `HTTP_422_UNPROCESSABLE_ENTITY` は非推奨で、`HTTP_422_UNPROCESSABLE_CONTENT` を使う。
  - 想定外の例外を `except Exception` で捕まえて `200` や `400` に変えていないか確認する（想定外の失敗は `500` のままにし、ログで追う）。
- **悪い例**:
  ```python
  if product is None:
      raise HTTPException(status_code=400, detail=f"product {product_id} not found in {Product.__table__}")
  ```
- **良い例**:
  ```python
  if product is None:
      raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="商品が見つかりません")
  ```

---

## 6. 設定と同期・非同期

### 6.1 `.env` からの設定の読み込み

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 機密性 ／ 移植性 > 適応性
- **確認内容**:
  - 新しい設定値（決済ゲートウェイの API キーなど）を `os.getenv` で読み、`backend/.env.example` にダミー値つきで追記しているか確認する。
  - 必須の秘密情報が未設定のとき、黙って既定値で動かず、起動時・使用時に分かるエラーにしているか確認する。
  - 数値の設定（トークンの有効期間の分数など）を `int()` で変換するとき、不正な値で分かりにくい例外にならないか確認する。
- **悪い例**:
  ```python
  API_KEY = os.getenv("PAYMENT_GATEWAY_API_KEY", "test-key")  # 未設定に気づけない
  ```
- **良い例**:
  ```python
  API_KEY = os.getenv("PAYMENT_GATEWAY_API_KEY")
  if not API_KEY:
      raise RuntimeError("PAYMENT_GATEWAY_API_KEY が設定されていません（.env.example を参照）")
  ```

### 6.2 `async def` の中のブロッキング処理

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 性能効率性 > 時間効率性 ／ 信頼性 > 可用性
- **確認内容**:
  - `async def` のエンドポイントの中で、同期の処理（SQLAlchemy の同期セッション・`bcrypt`・`requests` による外部 API 呼び出し）を直接呼んでいないか確認する（イベントループが止まり、他のリクエストも待たされる）。
  - 同期の処理を使うなら、既存と同じく `def` で定義しているか確認する（FastAPI がスレッドプールで実行する）。
- **悪い例**:
  ```python
  @router.post("/orders")
  async def checkout(db: Session = Depends(get_db)):
      cart_items = db.query(CartItem).all()  # 同期の DB アクセスでイベントループが止まる
  ```
- **良い例**:
  ```python
  @router.post("/orders")
  def checkout(db: Session = Depends(get_db)):
      cart_items = db.query(CartItem).all()
  ```

---

## 7. テスト（pytest）

### 7.1 フィクスチャと DB の分離

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 保守性 > 試験性 ／ 信頼性 > 成熟性
- **確認内容**:
  - テストは `conftest.py` の `client`・`db_session` フィクスチャを使い、開発用の DB（`SessionLocal`・`ecommerce.db`）に接続していないか確認する。
  - `app.dependency_overrides` を書き換えたら、テストの後で元に戻しているか確認する（既存の `client` フィクスチャは `clear()` している）。
  - フィクスチャのスコープを `session`・`module` に広げて、テスト間で DB の状態を共有していないか確認する。
  - 前提データ（商品・会員・注文）はフィクスチャかテストの中で作り、`seed.py` の初期データに依存していないか確認する。
- **悪い例**:
  ```python
  def test_checkout():
      client = TestClient(app)  # get_db が差し替わらず、開発用の DB を書き換える
  ```
- **良い例**:
  ```python
  def test_checkout(client, auth_headers, sample_product):
      ...
  ```

### 7.2 境界値は `parametrize`、時刻は差し替える

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 保守性 > 試験性 ／ 機能適合性 > 機能完全性
- **確認内容**:
  - 同じ手順で入力だけ変える境界値のテスト（区切りの値ちょうど・その前後）を、`@pytest.mark.parametrize` でまとめ、`ids` で意味が分かる名前を付けているか確認する。
  - 発送予定日など現在時刻に依存する処理を、`monkeypatch` で時刻を返す関数を差し替えるなどして、実行日によらず同じ結果にしているか確認する。
  - 例外の検証に `pytest.raises` を使い、例外の種類とメッセージまで確認しているか確認する。
- **悪い例**:
  ```python
  def test_shipping_fee():
      assert shipping_fee(2000) == 800
      assert shipping_fee(2001) == 1000  # どちらが落ちたか分かりにくい
  ```
- **良い例**:
  ```python
  @pytest.mark.parametrize(
      ("grams", "expected"), [(2000, 800), (2001, 1000)], ids=["at_threshold", "just_over"]
  )
  def test_shipping_fee(grams, expected):
      assert shipping_fee(grams) == expected
  ```
