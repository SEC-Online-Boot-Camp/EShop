import { NavLink, Outlet } from 'react-router'

import { useAuth } from '../auth/useAuth'

export function Layout() {
  const { token, logout } = useAuth()

  return (
    <>
      <header className="header">
        <h1 className="logo">EShop</h1>
        <nav className="nav">
          <NavLink to="/" end>
            商品一覧
          </NavLink>
          <NavLink to="/cart">カート</NavLink>
          {token ? (
            <button type="button" className="link-button" onClick={logout}>
              ログアウト
            </button>
          ) : (
            <NavLink to="/login">ログイン</NavLink>
          )}
        </nav>
      </header>
      <main className="main">
        <Outlet />
      </main>
    </>
  )
}
