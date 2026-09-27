import { createContext } from 'react'

export type AuthState = {
  token: string | null
  login: (email: string, password: string) => Promise<void>
  logout: () => void
}

export const AuthContext = createContext<AuthState | null>(null)
