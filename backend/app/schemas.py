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
    items: list[OrderItemOut]
    created_at: datetime
