from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from src.app.schemas import (
    CartItemCreate,
    CartItemOut,
    LoginRequest,
    OrderItemOut,
    OrderOut,
    ProductOut,
    TokenResponse,
)


class DummyProduct:
    def __init__(self):
        self.id = 1
        self.name = "dummy"
        self.price = 100
        self.category = "test"
        self.is_sale = False


class TestSchemas:
    def test_cart_item_create_default_quantity(self):
        payload = CartItemCreate(product_id=10)
        assert payload.quantity == 1

    def test_cart_item_create_rejects_zero_quantity(self):
        with pytest.raises(ValidationError):
            CartItemCreate(product_id=10, quantity=0)

    def test_token_response_default_token_type(self):
        token = TokenResponse(access_token="abc")
        assert token.token_type == "bearer"

    def test_product_out_accepts_attribute_object(self):
        out = ProductOut.model_validate(DummyProduct())
        assert out.id == 1
        assert out.name == "dummy"

    def test_product_out_rejects_wrong_type(self):
        with pytest.raises(ValidationError):
            ProductOut.model_validate(
                {
                    "id": "x",
                    "name": "dummy",
                    "price": 100,
                    "category": "test",
                    "is_sale": False,
                }
            )


class TestLoginRequestSchema:
    def test_missing_password_raises(self):
        with pytest.raises(ValidationError):
            LoginRequest(email="user@example.com")


class DummyCartItem:
    def __init__(self):
        self.product_id = 1
        self.product_name = "dummy"
        self.unit_price = 500
        self.quantity = 2


class TestCartItemOutSchema:
    def test_accepts_attribute_object(self):
        out = CartItemOut.model_validate(DummyCartItem())
        assert out.product_id == 1
        assert out.unit_price == 500


class TestOrderItemOutSchema:
    def test_accepts_attribute_object(self):
        out = OrderItemOut.model_validate(DummyCartItem())
        assert out.quantity == 2


class DummyOrder:
    def __init__(self):
        self.id = 1
        self.status = "confirmed"
        self.subtotal = 1000
        self.items = [DummyCartItem()]
        self.created_at = datetime.now(timezone.utc)


class TestOrderOutSchema:
    def test_accepts_attribute_object_with_nested_items(self):
        out = OrderOut.model_validate(DummyOrder())
        assert out.id == 1
        assert len(out.items) == 1
        assert out.items[0].product_id == 1
