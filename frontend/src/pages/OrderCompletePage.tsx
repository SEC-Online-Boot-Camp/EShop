import { Link, Navigate, useLocation } from 'react-router'

import type { Order } from '../api/types'
import { yen } from '../format'

// 注文一覧 API はないので、注文確定時の応答を遷移の state で受け取って表示する
export function OrderCompletePage() {
  const location = useLocation()
  const order = (location.state as { order?: Order } | null)?.order
  if (!order) return <Navigate to="/" replace />

  return (
    <section className="card">
      <h2>ご注文ありがとうございました</h2>
      <p>注文番号: {order.id}</p>
      <table className="table">
        <thead>
          <tr>
            <th>商品名</th>
            <th className="num">単価</th>
            <th className="num">数量</th>
          </tr>
        </thead>
        <tbody>
          {order.items.map((item) => (
            <tr key={item.product_id}>
              <td>{item.product_name}</td>
              <td className="num">{yen(item.unit_price)}</td>
              <td className="num">{item.quantity}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <dl className="summary">
        <dt className="total">お支払い金額</dt>
        <dd className="total">{yen(order.subtotal)}</dd>
      </dl>
      <Link to="/">商品一覧に戻る</Link>
    </section>
  )
}
