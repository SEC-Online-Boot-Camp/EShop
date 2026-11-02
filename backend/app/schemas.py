from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class LoginRequest(BaseModel):
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    price: int
    category: str
    is_sale: bool


class CartItemCreate(BaseModel):
    product_id: int
    quantity: int = Field(default=1, ge=1)


class CartItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    product_id: int
    product_name: str
    unit_price: int
    quantity: int


class CartOut(BaseModel):
    items: list[CartItemOut]
    subtotal: int
    # クーポン機能の項目。画面（frontend）が受け取る形だけを先に用意してある。
    # クーポン機能はまだ無いので、適用中のクーポンは無く、割引は0で、支払い金額は小計と同じ。
    applied_coupon_code: str | None = None
    discount_amount: int = 0
    total: int = 0


class CouponApplyRequest(BaseModel):
    coupon_code: str


class OrderItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    product_id: int
    product_name: str
    unit_price: int
    quantity: int


class OrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    status: str
    subtotal: int
    # クーポン機能の項目（CartOutと同じく、画面が受け取る形だけを先に用意してある）
    coupon_code: str | None = None
    discount_amount: int = 0
    items: list[OrderItemOut]
    created_at: datetime
