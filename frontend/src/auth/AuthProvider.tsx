import { useCallback, useMemo, useState } from 'react'
import type { ReactNode } from 'react'

import { api } from '../api/client'
import { AuthContext } from './context'

const STORAGE_KEY = 'eshop.token'

export function AuthProvider({ children }: { children: ReactNode }) {
  // 研修用の簡易実装として JWT を localStorage に保存している。
  // XSS があるとスクリプトから読み出せてしまう保存先である点に注意。
  const [token, setToken] = useState<string | null>(() =>
    localStorage.getItem(STORAGE_KEY),
  )

  const login = useCallback(async (email: string, password: string) => {
    const res = await api.login(email, password)
    localStorage.setItem(STORAGE_KEY, res.access_token)
    setToken(res.access_token)
  }, [])

  const logout = useCallback(() => {
    localStorage.removeItem(STORAGE_KEY)
    setToken(null)
  }, [])

  const value = useMemo(() => ({ token, login, logout }), [token, login, logout])
  return <AuthContext value={value}>{children}</AuthContext>
}
