import pytest
from fastapi import HTTPException

from app import coupon as coupon_module
from app.models import CartItem


def cart_item(product, quantity):
    """DBに保存しないカートの明細。計算に使う商品と数量だけを持たせる。"""
    return CartItem(product=product, quantity=quantity)


class TestFindCoupon:
    def test_find_coupon_raises_404_for_unknown_code(self, db_session):
        with pytest.raises(HTTPException) as exc:
            coupon_module.find_coupon(db_session, "NOSUCHCODE")

        assert exc.value.status_code == 404


class TestCalcEligibleSubtotal:
    def test_sums_price_times_quantity(self, make_product, make_coupon):
        coupon = make_coupon()
        items = [
            cart_item(make_product(price=1000), 2),
            cart_item(make_product(price=1500), 1),
        ]

        assert coupon_module.calc_eligible_subtotal(items, coupon) == 3500

    def test_skips_excluded_categories(self, make_product, make_coupon):
        coupon = make_coupon(excluded_categories=["food"])
        items = [
            cart_item(make_product(price=1000, category="test"), 3),
            cart_item(make_product(price=2000, category="food"), 1),
        ]

        assert coupon_module.calc_eligible_subtotal(items, coupon) == 3000


class TestCalcDiscount:
    def test_fixed_coupon_discounts_its_value(self, make_coupon):
        coupon = make_coupon(type="fixed", value=500)

        assert coupon_module.calc_discount(coupon, 4000) == 500

    def test_fixed_coupon_does_not_exceed_eligible_subtotal(self, make_coupon):
        coupon = make_coupon(type="fixed", value=1000)

        assert coupon_module.calc_discount(coupon, 600) == 600

    def test_percentage_coupon_discounts_rate_of_subtotal(self, make_coupon):
        coupon = make_coupon(type="percentage", value=10)

        assert coupon_module.calc_discount(coupon, 5000) == 500

    def test_percentage_coupon_is_capped_by_max_discount_amount(self, make_coupon):
        coupon = make_coupon(type="percentage", value=10, max_discount_amount=1000)

        assert coupon_module.calc_discount(coupon, 20000) == 1000


class TestEvaluate:
    def test_returns_coupon_and_amounts(self, db_session, make_product, make_coupon):
        coupon = make_coupon(
            code="SPRING10", type="percentage", value=10, min_purchase_amount=3000
        )
        items = [cart_item(make_product(price=1000), 5)]

        got = coupon_module.evaluate(db_session, items, "SPRING10")

        assert got == (coupon, 5000, 500)

    def test_rejects_expired_coupon(self, db_session, make_product, make_coupon):
        make_coupon(code="EXPIRED", valid_from_days=-60, valid_to_days=-30)
        items = [cart_item(make_product(price=1000), 5)]

        with pytest.raises(HTTPException) as exc:
            coupon_module.evaluate(db_session, items, "EXPIRED")

        assert exc.value.status_code == 422

    def test_rejects_coupon_that_is_not_yet_valid(
        self, db_session, make_product, make_coupon
    ):
        make_coupon(code="FUTURE", valid_from_days=30, valid_to_days=60)
        items = [cart_item(make_product(price=1000), 5)]

        with pytest.raises(HTTPException) as exc:
            coupon_module.evaluate(db_session, items, "FUTURE")

        assert exc.value.status_code == 422


class TestConsume:
    def test_consume_increments_used_count(self, db_session, make_coupon):
        coupon = make_coupon(code="LIMIT3", usage_limit=3, used_count=1)

        assert coupon_module.consume(db_session, "LIMIT3") is True
        db_session.refresh(coupon)
        assert coupon.used_count == 2

    def test_consume_returns_false_when_usage_limit_reached(
        self, db_session, make_coupon
    ):
        coupon = make_coupon(code="LIMIT1", usage_limit=1, used_count=1)

        assert coupon_module.consume(db_session, "LIMIT1") is False
        db_session.refresh(coupon)
        assert coupon.used_count == 1
