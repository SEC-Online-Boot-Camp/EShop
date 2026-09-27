import { vi } from 'vitest'

type Handler = (body: unknown) => { status?: number; body: unknown }

// "POST /api/cart/items" のようなキーで応答を定義し、fetch を差し替える
export function mockFetch(routes: Record<string, Handler>) {
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    const key = `${init?.method ?? 'GET'} ${url}`
    const handler = routes[key]
    if (!handler) throw new Error(`モック未定義のリクエスト: ${key}`)
    const reqBody = init?.body ? JSON.parse(init.body as string) : undefined
    const { status = 200, body } = handler(reqBody)
    return new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json' },
    })
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}
