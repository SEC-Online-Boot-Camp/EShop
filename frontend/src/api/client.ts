import type { Cart, Order, Product, TokenResponse } from './types'

// vite.config.ts のプロキシで /api をバックエンドに転送している
const BASE_URL = '/api'

export class ApiError extends Error {
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

// FastAPI のエラー応答は {"detail": "..."} が基本だが、入力検証エラー（422）では
// {"detail": [{"msg": "...", ...}]} の配列になる。どちらでも表示できる文字列にする。
function toMessage(body: unknown, status: number): string {
  const detail = (body as { detail?: unknown } | null)?.detail
  if (typeof detail === 'string') return detail
  if (Array.isArray(detail)) {
    return detail
      .map((d) => (d as { msg?: string }).msg ?? '')
      .filter(Boolean)
      .join(' / ')
  }
  return `通信エラーが発生しました（${status}）`
}

async function request<T>(
  path: string,
  options: { method?: string; body?: unknown; token?: string | null } = {},
): Promise<T> {
  const headers: Record<string, string> = {}
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'
  if (options.token) headers['Authorization'] = `Bearer ${options.token}`

  const res = await fetch(`${BASE_URL}${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  })

  const body: unknown = await res.json().catch(() => null)
  if (!res.ok) throw new ApiError(res.status, toMessage(body, res.status))
  return body as T
}

export const api = {
  login: (email: string, password: string) =>
    request<TokenResponse>('/auth/login', {
      method: 'POST',
      body: { email, password },
    }),

  listProducts: () => request<Product[]>('/products'),

  getCart: (token: string) => request<Cart>('/cart', { token }),

  addCartItem: (token: string, productId: number, quantity: number) =>
    request<Cart>('/cart/items', {
      method: 'POST',
      token,
      body: { product_id: productId, quantity },
    }),

  checkout: (token: string) =>
    request<Order>('/orders', { method: 'POST', token }),
}
