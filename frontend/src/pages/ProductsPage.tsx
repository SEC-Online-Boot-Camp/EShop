import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router'

import { ApiError, api } from '../api/client'
import type { Product } from '../api/types'
import { useAuth } from '../auth/useAuth'
import { yen } from '../format'

export function ProductsPage() {
  const { token, logout } = useAuth()
  const navigate = useNavigate()

  const [products, setProducts] = useState<Product[] | null>(null)
  const [quantities, setQuantities] = useState<Record<number, number>>({})
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .listProducts()
      .then(setProducts)
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '商品を取得できませんでした'),
      )
  }, [])

  async function handleAdd(product: Product) {
    // 商品一覧はログイン不要だが、カート操作にはログインが要る
    if (!token) {
      navigate('/login', { state: { from: '/' } })
      return
    }
    setMessage(null)
    setError(null)
    try {
      await api.addCartItem(token, product.id, quantities[product.id] ?? 1)
      setMessage(`「${product.name}」をカートに追加しました`)
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        logout()
        navigate('/login', { state: { from: '/' } })
        return
      }
      setError(err instanceof ApiError ? err.message : 'カートに追加できませんでした')
    }
  }

  return (
    <section className="card">
      <h2>商品一覧</h2>
      {message && <p className="notice" role="status">{message}</p>}
      {error && <p className="error" role="alert">{error}</p>}
      {products === null ? (
        !error && <p>読み込み中…</p>
      ) : (
        <table className="table">
          <thead>
            <tr>
              <th>商品名</th>
              <th>カテゴリ</th>
              <th className="num">価格</th>
              <th>数量</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {products.map((p) => (
              <tr key={p.id}>
                <td>
                  {p.name}
                  {p.is_sale && <span className="badge">セール</span>}
                </td>
                <td>{p.category}</td>
                <td className="num">{yen(p.price)}</td>
                <td>
                  <input
                    type="number"
                    min={1}
                    className="qty"
                    aria-label={`${p.name}の数量`}
                    value={quantities[p.id] ?? 1}
                    onChange={(e) =>
                      setQuantities({
                        ...quantities,
                        [p.id]: Math.max(1, Number(e.target.value) || 1),
                      })
                    }
                  />
                </td>
                <td>
                  <button type="button" onClick={() => handleAdd(p)}>
                    カートに入れる
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  )
}
