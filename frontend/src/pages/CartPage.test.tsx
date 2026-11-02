import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router'
import { describe, expect, it, vi } from 'vitest'

import type { Cart } from '../api/types'
import { AuthContext } from '../auth/context'
import { mockFetch } from '../test/mockFetch'
import { CartPage } from './CartPage'

const baseCart: Cart = {
  items: [
    { product_id: 2, product_name: 'メカニカルキーボード', unit_price: 12800, quantity: 1 },
  ],
  subtotal: 12800,
  applied_coupon_code: null,
  discount_amount: 0,
  total: 12800,
}

const discounted: Cart = {
  ...baseCart,
  applied_coupon_code: 'SPRING10',
  discount_amount: 1000,
  total: 11800,
}

function renderCart() {
  const auth = { token: 'tok', login: vi.fn(), logout: vi.fn() }
  render(
    <AuthContext value={auth}>
      <MemoryRouter initialEntries={['/cart']}>
        <Routes>
          <Route path="/cart" element={<CartPage />} />
          <Route path="/orders/complete" element={<p>注文完了画面</p>} />
        </Routes>
      </MemoryRouter>
    </AuthContext>,
  )
  return auth
}

describe('CartPage', () => {
  it('クーポンを適用すると割引額と支払金額が表示される', async () => {
    let cart = baseCart
    mockFetch({
      'GET /api/cart': () => ({ body: cart }),
      'POST /api/cart/coupon': (req) => {
        expect(req).toEqual({ coupon_code: 'SPRING10' })
        cart = discounted
        return {
          body: {
            coupon_code: 'SPRING10',
            eligible_subtotal: 12800,
            discount_amount: 1000,
            subtotal: 12800,
            total: 11800,
          },
        }
      },
    })
    renderCart()

    await userEvent.type(await screen.findByLabelText('クーポンコード'), ' SPRING10 ')
    await userEvent.click(screen.getByRole('button', { name: '適用' }))

    expect(await screen.findByText('SPRING10')).toBeInTheDocument()
    expect(screen.getByText('−1,000円')).toBeInTheDocument()
    expect(screen.getByText('11,800円')).toBeInTheDocument()
  })

  it('適用できないクーポンはバックエンドのエラー文言を表示する', async () => {
    mockFetch({
      'GET /api/cart': () => ({ body: baseCart }),
      'POST /api/cart/coupon': () => ({
        status: 422,
        body: { detail: '最低購入金額を満たしていません' },
      }),
    })
    renderCart()

    await userEvent.type(await screen.findByLabelText('クーポンコード'), 'FLAT500')
    await userEvent.click(screen.getByRole('button', { name: '適用' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      '最低購入金額を満たしていません',
    )
  })

  it('適用中のクーポンが条件を満たさなくなったら警告を出す', async () => {
    mockFetch({
      'GET /api/cart': () => ({
        body: { ...baseCart, applied_coupon_code: 'SPRING10', discount_amount: 0 },
      }),
    })
    renderCart()

    expect(await screen.findByText(/適用条件を満たしていません/)).toBeInTheDocument()
  })

  it('注文確定時に表示中の支払金額を expected_total として送る', async () => {
    const checkout = vi.fn(() => ({
      status: 201,
      body: {
        id: 1,
        status: 'confirmed',
        subtotal: 12800,
        coupon_code: 'SPRING10',
        discount_amount: 1000,
        items: discounted.items,
        created_at: '2026-09-27T00:00:00',
      },
    }))
    mockFetch({
      'GET /api/cart': () => ({ body: discounted }),
      'POST /api/orders': checkout,
    })
    renderCart()

    await userEvent.click(await screen.findByRole('button', { name: '注文を確定する' }))

    expect(await screen.findByText('注文完了画面')).toBeInTheDocument()
    expect(checkout).toHaveBeenCalledWith({ expected_total: 11800 })
  })

  it('トークン切れ（401）ならログアウトする', async () => {
    mockFetch({
      'GET /api/cart': () => ({ status: 401, body: { detail: '認証情報が無効です' } }),
    })
    const auth = renderCart()

    await vi.waitFor(() => expect(auth.logout).toHaveBeenCalled())
  })
})
