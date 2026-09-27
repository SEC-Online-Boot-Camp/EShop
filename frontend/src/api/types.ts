// バックエンドの src/app/schemas.py と対応させた型定義。
// schemas.py を変更したら、こちらも合わせて更新すること。

export type TokenResponse = {
  access_token: string
  token_type: string
}

export type Product = {
  id: number
  name: string
  price: number
  category: string
  is_sale: boolean
}

export type CartItem = {
  product_id: number
  product_name: string
  unit_price: number
  quantity: number
}

export type Cart = {
  items: CartItem[]
  subtotal: number
  applied_coupon_code: string | null
  discount_amount: number
  total: number
}

export type CouponApplyResult = {
  coupon_code: string
  eligible_subtotal: number
  discount_amount: number
  subtotal: number
  total: number
}

export type OrderItem = CartItem

export type Order = {
  id: number
  status: string
  subtotal: number
  coupon_code: string | null
  discount_amount: number
  items: OrderItem[]
  created_at: string
}
