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
    { product_id: 1, product_name: 'ワイヤレスマウス', unit_price: 2980, quantity: 2 },
    { product_id: 2, product_name: 'メカニカルキーボード', unit_price: 12800, quantity: 1 },
  ],
  subtotal: 18760,
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
  it('明細ごとの小計と支払金額を表示する', async () => {
    mockFetch({ 'GET /api/cart': () => ({ body: baseCart }) })
    renderCart()

    expect(await screen.findByText('5,960円')).toBeInTheDocument()
    expect(screen.getByText('18,760円')).toBeInTheDocument()
  })

  it('空のカートでは注文ボタンを出さない', async () => {
    mockFetch({ 'GET /api/cart': () => ({ body: { items: [], subtotal: 0 } }) })
    renderCart()

    expect(await screen.findByText('カートは空です。')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: '注文を確定する' })).toBeNull()
  })

  it('注文を確定すると注文完了画面へ進む', async () => {
    const checkout = vi.fn(() => ({
      status: 201,
      body: {
        id: 1,
        status: 'confirmed',
        subtotal: 18760,
        items: baseCart.items,
        created_at: '2026-09-27T00:00:00',
      },
    }))
    mockFetch({
      'GET /api/cart': () => ({ body: baseCart }),
      'POST /api/orders': checkout,
    })
    renderCart()

    await userEvent.click(await screen.findByRole('button', { name: '注文を確定する' }))

    expect(await screen.findByText('注文完了画面')).toBeInTheDocument()
    expect(checkout).toHaveBeenCalledOnce()
  })

  it('注文を確定できなければバックエンドのエラー文言を表示する', async () => {
    mockFetch({
      'GET /api/cart': () => ({ body: baseCart }),
      'POST /api/orders': () => ({ status: 400, body: { detail: 'カートが空です' } }),
    })
    renderCart()

    await userEvent.click(await screen.findByRole('button', { name: '注文を確定する' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('カートが空です')
  })

  it('トークン切れ（401）ならログアウトする', async () => {
    mockFetch({
      'GET /api/cart': () => ({ status: 401, body: { detail: '認証情報が無効です' } }),
    })
    const auth = renderCart()

    await vi.waitFor(() => expect(auth.logout).toHaveBeenCalled())
  })
})
