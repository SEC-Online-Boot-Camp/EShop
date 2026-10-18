import { Navigate, Route, Routes } from 'react-router'

import { RequireAuth } from './auth/RequireAuth'
import { Layout } from './components/Layout'
import { CartPage } from './pages/CartPage'
import { LoginPage } from './pages/LoginPage'
import { OrderCompletePage } from './pages/OrderCompletePage'
import { ProductsPage } from './pages/ProductsPage'

export function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<ProductsPage />} />
        <Route path="login" element={<LoginPage />} />
        <Route
          path="cart"
          element={
            <RequireAuth>
              <CartPage />
            </RequireAuth>
          }
        />
        <Route
          path="orders/complete"
          element={
            <RequireAuth>
              <OrderCompletePage />
            </RequireAuth>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
