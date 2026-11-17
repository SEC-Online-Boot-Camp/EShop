import { use } from 'react'

import { AuthContext } from './context'

export function useAuth() {
  const auth = use(AuthContext)
  if (auth === null) throw new Error('useAuth は AuthProvider の内側で使うこと')
  return auth
}
