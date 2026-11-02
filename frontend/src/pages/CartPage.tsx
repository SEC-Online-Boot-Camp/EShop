import { useCallback, useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate } from 'react-router'

import { ApiError, api } from '../api/client'
import type { Cart } from '../api/types'
import { useAuth } from '../auth/useAuth'
import { yen } from '../format'

export function CartPage() {
  // RequireAuth の内側でだけ描画するので token は必ずある
  const { token, logout } = useAuth() as { token: string; logout: () => void }
  const navigate = useNavigate()

  const [cart, setCart] = useState<Cart | null>(null)
  const [couponCode, setCouponCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const handleError = useCallback(
    (err: unknown, fallback: string) => {
      if (err instanceof ApiError && err.status === 401) {
        logout() // トークン切れ。RequireAuth がログイン画面へ戻す
        return
      }
      setError(err instanceof ApiError ? err.message : fallback)
    },
    [logout],
  )

  const reload = useCallback(async () => {
    try {
      setCart(await api.getCart(token))
    } catch (err) {
      handleError(err, 'カートを取得できませんでした')
    }
  }, [token, handleError])

  useEffect(() => {
    api
      .getCart(token)
      .then(setCart)
      .catch((err: unknown) => handleError(err, 'カートを取得できませんでした'))
  }, [token, handleError])

  async function run(action: () => Promise<void>, fallback: string) {
    setError(null)
    setBusy(true)
    try {
      await action()
    } catch (err) {
      handleError(err, fallback)
    } finally {
      setBusy(false)
    }
  }

  function handleApplyCoupon(e: FormEvent) {
    e.preventDefault()
    const code = couponCode.trim()
    if (!code) return
    void run(async () => {
      await api.applyCoupon(token, code)
      setCouponCode('')
      await reload()
    }, 'クーポンを適用できませんでした')
  }

  function handleRemoveCoupon() {
    void run(async () => {
      setCart(await api.removeCoupon(token))
    }, 'クーポンを解除できませんでした')
  }

  function handleCheckout(current: Cart) {
    void run(async () => {
      try {
        const order = await api.checkout(token, current.total)
        navigate('/orders/complete', { state: { order } })
      } catch (err) {
        // 金額の不一致などで確定できなかったときは、最新の金額を表示し直す
        await reload()
        throw err
      }
    }, '注文を確定できませんでした')
  }

  if (cart === null) {
    return (
      <section className="card">
        <h2>カート</h2>
        {error ? <p className="error" role="alert">{error}</p> : <p>読み込み中…</p>}
      </section>
    )
  }

  // 適用後にカート内容が変わって条件を満たさなくなると、コードは残ったまま割引が0になる
  const couponNotEligible =
    cart.applied_coupon_code !== null && cart.discount_amount === 0

  return (
    <section className="card">
      <h2>カート</h2>
      {error && <p className="error" role="alert">{error}</p>}

      {cart.items.length === 0 ? (
        <p>カートは空です。</p>
      ) : (
        <>
          <table className="table">
            <thead>
              <tr>
                <th>商品名</th>
                <th className="num">単価</th>
                <th className="num">数量</th>
                <th className="num">小計</th>
              </tr>
            </thead>
            <tbody>
              {cart.items.map((item) => (
                <tr key={item.product_id}>
                  <td>{item.product_name}</td>
                  <td className="num">{yen(item.unit_price)}</td>
                  <td className="num">{item.quantity}</td>
                  <td className="num">{yen(item.unit_price * item.quantity)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="coupon">
            {cart.applied_coupon_code === null ? (
              <form onSubmit={handleApplyCoupon} className="inline-form">
                <label>
                  クーポンコード
                  <input
                    value={couponCode}
                    onChange={(e) => setCouponCode(e.target.value)}
                    placeholder="例: SPRING10"
                  />
                </label>
                <button type="submit" disabled={busy || !couponCode.trim()}>
                  適用
                </button>
              </form>
            ) : (
              <p>
                適用中のクーポン: <strong>{cart.applied_coupon_code}</strong>{' '}
                <button
                  type="button"
                  className="link-button"
                  onClick={handleRemoveCoupon}
                  disabled={busy}
                >
                  解除
                </button>
              </p>
            )}
            {couponNotEligible && (
              <p className="warning" role="status">
                現在のカート内容ではクーポンの適用条件を満たしていません。
                このまま注文を確定するとエラーになります。
              </p>
            )}
          </div>

          <dl className="summary">
            <dt>小計</dt>
            <dd>{yen(cart.subtotal)}</dd>
            <dt>割引</dt>
            <dd>{cart.discount_amount > 0 ? `−${yen(cart.discount_amount)}` : yen(0)}</dd>
            <dt className="total">お支払い金額</dt>
            <dd className="total">{yen(cart.total)}</dd>
          </dl>

          <button
            type="button"
            className="primary"
            onClick={() => handleCheckout(cart)}
            disabled={busy}
          >
            注文を確定する
          </button>
        </>
      )}
    </section>
  )
}
