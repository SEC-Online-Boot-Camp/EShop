---
layer: stack
target: typescript-react
---

# TypeScript + React スタックのレビュー観点

> 凡例（重要度 Must/Should/Nit の定義、ISO/IEC 25010 の8品質特性一覧）は [../README.md](../README.md) を参照してください。

**TypeScript + React 19 + Vite + react-router、Vitest + Testing Library、JWT を `Authorization: Bearer` で送る画面**（`frontend/`）を前提とした、スタック固有の観点です。
汎用観点（common / phases）では拾いきれない具体（hooks の規則・型機能・fetch の落とし穴・テストの書き方）に徹します。

> **層間の線引き**:
>
> - common.md の「認証・認可の欠落」や `03-basic-design.md` の「トークン方式の設計」とは重複させない（この合成では対象外・言及不要）。
>   ここでは**画面での具体的な扱い**（トークンの保存先、401 を受けたときの振る舞い、`dangerouslySetInnerHTML` など）に絞る。
> - `05-implementation.md` の「型で不正状態を排除する（言語非依存）」に対し、ここでは**TypeScript 固有の型機能**を扱う。
> - JWT の発行・検証（`exp`・署名アルゴリズム）と、金額の計算そのものは `stacks/python-fastapi.md` の担当（この合成では対象外・言及不要）。

---

## 1. 型安全性（TypeScript 固有）

### 1.1 `any` の濫用

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 保守性 > 解析性 ／ 信頼性 > 成熟性
- **確認内容**:
  - `any` で型チェックを無効化していないか確認する（特に API の応答・`catch` の引数・イベント）。
  - 型が不明な値には `any` ではなく `unknown` を使い、絞り込み後に扱っているか確認する（既存の `catch (err: unknown)` と `err instanceof ApiError` の流儀）。
  - `tsconfig` の `strict`（`strictNullChecks`・`noImplicitAny` 等）が有効か確認する。無効のまま `null` の可能性がある値を扱う変更は、実行時に落ちないかを特に確認する。
- **悪い例**:
  ```ts
  } catch (err: any) {
    setError(err.message) // ApiError 以外（ネットワーク断など）でも message があるとは限らない
  }
  ```
- **良い例**:
  ```ts
  } catch (err: unknown) {
    setError(err instanceof ApiError ? err.message : 'カートを取得できませんでした')
  }
  ```

### 1.2 型アサーション・非 null アサーションの乱用

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 成熟性 ／ 保守性 > 解析性
- **確認内容**:
  - `as` による型アサーションで実体と異なる型を強制していないか確認する。アサーションを使うなら、それが成り立つ理由がコメントで説明されているか確認する。
  - `!`（非 null アサーション）で `null`/`undefined` の可能性を握りつぶしていないか確認する。
- **悪い例**:
  ```ts
  const { token } = useAuth() as { token: string } // RequireAuth の外で使われると null のまま進む
  ```
- **良い例**:
  ```ts
  const { token } = useAuth()
  if (!token) return <Navigate to="/login" replace /> // 絞り込みで型が確定
  ```

### 1.3 API の応答と型定義の一致

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 機能適合性 > 機能正確性 ／ 互換性 > 相互運用性
- **確認内容**:
  - `frontend/src/api/types.ts`（手書き）が、`backend/app/schemas.py` の応答と項目名・型・`null` の可否まで一致しているか確認する（`schemas.py` を変えた PR で `types.ts` が直っているか）。
  - `request<T>()` の `as T` は応答を検証しないため、型を信じて進むと画面が壊れる箇所（項目の欠落・`null`）に手当てがあるか確認する。
- **悪い例**:
  ```ts
  export type Cart = { items: CartItem[]; subtotal: number; shipping: number } // API は shipping_fee を返す
  ```
- **良い例**:
  ```ts
  // backend/app/schemas.py の CartOut と対応
  export type Cart = { items: CartItem[]; subtotal: number; shipping_fee: number; total: number }
  ```

---

## 2. hooks（React 固有）

### 2.1 hooks の呼び出し規則と依存配列

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 成熟性 ／ 機能適合性 > 機能正確性
- **確認内容**:
  - hooks を条件分岐・ループ・早期 return の後で呼んでいないか確認する（oxlint の `react/rules-of-hooks` が検出する）。
  - `useEffect`・`useCallback`・`useMemo` の依存配列に、中で使う値（`token`・props・state・関数）が漏れなく入っているか確認する。oxlint は依存配列の漏れを `react-hooks(exhaustive-deps)` の**警告**として出すが、警告では CI が落ちないため、警告を残したまま・`// oxlint-disable` で黙らせたままの変更がないか確認する。
  - 依存配列に毎回作り直されるオブジェクト・関数を入れて、effect が無限に再実行されていないか確認する。
- **悪い例**:
  ```ts
  useEffect(() => {
    api.getCart(token).then(setCart)
  }, []) // token が変わっても（ログインし直しても）古いトークンのまま
  ```
- **良い例**:
  ```ts
  useEffect(() => {
    api.getCart(token).then(setCart).catch((err: unknown) => handleError(err, 'カートを取得できませんでした'))
  }, [token, handleError])
  ```

### 2.2 effect 内の setState と派生 state

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 保守性 > 解析性 ／ 性能効率性 > 時間効率性
- **確認内容**:
  - props や他の state から計算できる値を、`useEffect` の中で `setState` して「同期」していないか確認する（描画中に計算すれば足りる）。oxlint の `react(set-state-in-effect)` も警告を出すが、CI は落ちない。
  - 非同期処理の結果を `setState` するとき、画面を離れた後や、後から出したリクエストの結果を古い結果で上書きしないか確認する（effect の後始末で無視する・`AbortController` で中断する）。
- **悪い例**:
  ```ts
  const [count, setCount] = useState(0)
  useEffect(() => {
    setCount(cart.items.reduce((n, i) => n + i.quantity, 0)) // 1回余分に描画され、一瞬ずれた値が出る
  }, [cart])
  ```
- **良い例**:
  ```ts
  const count = cart.items.reduce((n, i) => n + i.quantity, 0) // 描画中に計算する
  ```

### 2.3 リストの key

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 成熟性
- **確認内容**:
  - リストの `key` に、並び替え・削除で変わる配列の添字ではなく、項目を一意に表す ID（`product_id` など）を使っているか確認する。
- **悪い例**: `cart.items.map((item, i) => <tr key={i}>…)`（明細を消すと、入力中の数量が別の行に移る）
- **良い例**: `cart.items.map((item) => <tr key={item.product_id}>…)`

---

## 3. 非同期処理と API 呼び出し

### 3.1 fetch のエラー処理

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 障害許容性 ／ 使用性 > ユーザーエラー防止性
- **確認内容**:
  - `fetch` は 4xx・5xx でも例外にならないため、`res.ok` を確かめてから応答を使っているか確認する（API の呼び出しは既存の `api/client.ts` の `request()` を通し、直接 `fetch` しない）。
  - ネットワーク断・JSON でない応答でも、画面が固まらずエラーを表示するか確認する。
  - Promise を投げっぱなしにしてエラーを失っていないか（`.catch` も `await` もない呼び出し）確認する。
- **悪い例**:
  ```ts
  const res = await fetch(`/api/products/${productId}/reviews`, { method: 'POST', body })
  setReviews([...reviews, await res.json()]) // 422 のエラー応答をレビューとして表示してしまう
  ```
- **良い例**:
  ```ts
  try {
    const review = await api.postReview(token, productId, input) // request() が !res.ok を ApiError にする
    setReviews([...reviews, review])
  } catch (err: unknown) {
    handleError(err, 'レビューを投稿できませんでした')
  }
  ```

### 3.2 401（トークン切れ）の扱い

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 真正性 ／ 使用性 > 運用操作性
- **確認内容**:
  - 要ログインの API が `401` を返したとき、トークンを破棄してログイン画面へ戻しているか確認する（既存の `CartPage` の `handleError` と同じ扱い）。
  - `401` をほかのエラーと同じく文言表示だけで済ませ、期限切れのトークンを使い続けていないか確認する。
  - ログイン後に元の画面へ戻す遷移先を、外部の URL にできないか確認する（アプリ内のパスに限る）。
- **悪い例／良い例**: 新しい画面で `ApiError` の `status` を見ずに `err.message` を表示するだけにせず、`status === 401` なら `logout()` してログイン画面へ戻す。

### 3.3 二重送信の防止

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 使用性 > ユーザーエラー防止性 ／ 信頼性 > 成熟性
- **確認内容**:
  - 注文確定・レビューの投稿など状態を変える操作で、処理中はボタンを押せないようにしているか確認する（既存の `busy` の扱い）。
  - 処理が失敗したときに、押せない状態のまま戻らなくならないか（`finally` で戻しているか）確認する。
- **悪い例／良い例**: 「注文を確定する」ボタンを連打すると `POST /orders` が2回飛ぶ実装にせず、送信中は `disabled` にし、`finally` で戻す。

---

## 4. 画面のセキュリティ

### 4.1 XSS と `dangerouslySetInnerHTML`

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 完全性 / 機密性
- **確認内容**:
  - API の応答や入力値（商品名・レビュー本文・エラー文言など）を `dangerouslySetInnerHTML` で HTML として埋め込んでいないか確認する。どうしても HTML を出すなら、サニタイズ（DOMPurify 等）しているか確認する。
  - `href`・`src` に外部由来の値を入れる場合、`javascript:` などのスキームを弾いているか確認する。
- **悪い例**:
  ```tsx
  <p dangerouslySetInnerHTML={{ __html: review.body }} />
  ```
- **良い例**:
  ```tsx
  <p>{review.body}</p> {/* JSX の埋め込みは自動でエスケープされる */}
  ```

### 4.2 トークンと秘密情報の置き場所

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: セキュリティ > 機密性
- **確認内容**:
  - JWT の保存先を広げていないか確認する（EShop は研修用の割り切りとして `localStorage` に保存している。`frontend/README.md` の「既知の割り切り」）。トークンをログ・URL のクエリ・エラー表示に出していないか確認する。
  - 保存先を HttpOnly Cookie に変える場合、CSRF 対策（`SameSite` やトークン）もあわせて設計されているか確認する。
  - 決済ゲートウェイの秘密の API キーなどを、画面のコードや `VITE_` で始まる環境変数に置いていないか確認する（`VITE_` の値はビルド結果に埋め込まれ、誰でも読める）。
  - 対象システムの公開範囲（社内限定／認証必須／一般公開）を踏まえて重要度を判断する。秘密の API キーを画面に置いている場合は Must とする。
- **悪い例**:
  ```ts
  const key = import.meta.env.VITE_PAYMENT_GATEWAY_API_KEY // ブラウザに配信される
  ```
- **良い例**: 決済ゲートウェイの呼び出しはバックエンドだけが行い、API キーは `backend/.env` に置く。画面はバックエンドの API を呼ぶだけにする。

---

## 5. 金額の表示

### 5.1 金額はサーバーの値を表示する

- **重要度**: Must
- **品質特性 (ISO/IEC 25010)**: 機能適合性 > 機能正確性 ／ セキュリティ > 完全性
- **確認内容**:
  - 支払金額・送料・消費税を画面で独自に計算して表示・送信していないか確認する（計算の正はサーバー。画面で計算するとサーバーと食い違い、送った金額を信用されると改ざんできる）。
  - 金額の表示に既存の `yen()`（`frontend/src/format.ts`）を使っているか確認する。
- **悪い例**:
  ```tsx
  <dd>{yen(cart.subtotal + 800)}</dd> {/* 送料を画面が決め打ちで足している（地域で変わるとずれる） */}
  ```
- **良い例**:
  ```tsx
  <dd>{yen(cart.total)}</dd> {/* サーバーが計算した支払金額を表示する */}
  ```

---

## 6. テスト（Vitest + Testing Library）

### 6.1 利用者から見える要素で検証する

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 保守性 > 試験性 / 修正性
- **確認内容**:
  - 要素の取得に、ロール・ラベル・表示文言（`getByRole`・`getByLabelText`・`getByText`）を使っているか確認する。`className`・`data-testid`・コンポーネントの内部 state に依存していないか確認する。
  - 操作は `fireEvent` より `userEvent`（実際の利用者の操作に近い）を使っているか確認する。
- **悪い例**:
  ```ts
  container.querySelector('.primary')!.click()
  ```
- **良い例**:
  ```ts
  await userEvent.click(await screen.findByRole('button', { name: '注文を確定する' }))
  ```

### 6.2 非同期の表示を待つ

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 信頼性 > 成熟性 ／ 保守性 > 試験性
- **確認内容**:
  - API の応答後に出る表示を、`findBy*`・`waitFor` で待ってから検証しているか確認する（`getBy*` をすぐ呼ぶと、たまたま間に合ったときだけ通る）。
  - 「表示されないこと」の検証が、読み込み完了を待ってから行われているか確認する（待たずに `queryBy*` が `null` なのは当然）。
- **悪い例**:
  ```ts
  renderCart()
  expect(screen.queryByRole('button', { name: '注文を確定する' })).toBeNull() // 読み込み中なので当然 null
  ```
- **良い例**:
  ```ts
  renderCart()
  expect(await screen.findByText('カートは空です。')).toBeInTheDocument() // 読み込み完了を待つ
  expect(screen.queryByRole('button', { name: '注文を確定する' })).toBeNull()
  ```

### 6.3 fetch のモック

- **重要度**: Should
- **品質特性 (ISO/IEC 25010)**: 機能適合性 > 機能正確性 ／ 保守性 > 試験性
- **確認内容**:
  - API は既存の `mockFetch`（`frontend/src/test/mockFetch.ts`）でメソッドとパスごとに定義し、定義していないリクエストがエラーになる状態を保っているか確認する（呼ぶはずのない API を呼んでいても気づける）。
  - モックの応答が実際のバックエンドの形（`{"detail": "..."}`、422 の配列形式、ステータスコード）に沿っているか確認する。
  - 送ったリクエストの中身（商品 ID・数量・レビュー本文）を検証すべきテストで、モックの呼び出し引数を確認しているか確認する。
- **悪い例／良い例**: どの URL にも同じ応答を返す `vi.fn()` で `fetch` を丸ごと差し替えず、`mockFetch({ 'POST /api/cart/items': … })` のように呼び出しごとに定義する。
