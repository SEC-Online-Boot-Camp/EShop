import { describe, expect, it } from 'vitest'

import { mockFetch } from '../test/mockFetch'
import { ApiError, api } from './client'

describe('api client', () => {
  it('トークンを Authorization ヘッダーに付けて送る', async () => {
    const fetchMock = mockFetch({
      'GET /api/cart': () => ({
        body: { items: [], subtotal: 0, applied_coupon_code: null, discount_amount: 0, total: 0 },
      }),
    })

    await api.getCart('tok123')

    const init = fetchMock.mock.calls[0][1] as RequestInit
    expect(init.headers).toMatchObject({ Authorization: 'Bearer tok123' })
  })

  it('detail が文字列のエラーはそのままメッセージにする', async () => {
    mockFetch({
      'POST /api/cart/coupon': () => ({
        status: 404,
        body: { detail: 'クーポンが見つかりません' },
      }),
    })

    const err = await api.applyCoupon('t', 'NOPE').catch((e: unknown) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect(err).toMatchObject({ status: 404, message: 'クーポンが見つかりません' })
  })

  it('入力検証エラー（detail が配列）は msg をつないでメッセージにする', async () => {
    mockFetch({
      'POST /api/cart/items': () => ({
        status: 422,
        body: {
          detail: [
            { loc: ['body', 'quantity'], msg: 'Input should be greater than or equal to 1' },
          ],
        },
      }),
    })

    await expect(api.addCartItem('t', 1, 0)).rejects.toThrow(
      'Input should be greater than or equal to 1',
    )
  })
})
