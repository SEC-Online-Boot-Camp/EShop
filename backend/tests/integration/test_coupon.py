from datetime import timedelta

import pytest

from app.coupon import utcnow


class TestApplyCoupon:
    def test_apply_percentage_coupon_previews_discount(
        self, client, auth_headers, cart_with_items, sample_coupon
    ):
        """CPN-01 定率クーポンを適用すると、割引対象額×割合の割引額がプレビューされる。"""
        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["coupon_code"] == "SPRING10"
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 400
        assert body["subtotal"] == 4000
        assert body["total"] == 3600

    def test_apply_fixed_coupon_previews_discount(
        self, client, auth_headers, cart_with_items, fixed_coupon
    ):
        """CPN-02 定額クーポンを適用すると、クーポンの値の割引額がプレビューされる。"""
        response = client.post(
            "/cart/coupon", json={"coupon_code": "FLAT500"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["coupon_code"] == "FLAT500"
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 500
        assert body["subtotal"] == 4000
        assert body["total"] == 3500


class TestMinPurchaseAmountBoundary:
    def test_apply_coupon_rejected_one_yen_below_min_purchase(
        self, client, auth_headers, make_product, fixed_coupon
    ):
        """CPN-04 割引対象額が最低購入金額より1円少ないと、クーポンを適用できない。"""
        product = make_product(price=2999)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "FLAT500"}, headers=auth_headers
        )

        assert response.status_code == 422

    def test_apply_coupon_at_exact_min_purchase(
        self, client, auth_headers, make_product, fixed_coupon
    ):
        """CPN-05 割引対象額が最低購入金額ちょうどなら、クーポンを適用できる。"""
        product = make_product(price=3000)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "FLAT500"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 3000
        assert body["discount_amount"] == 500
        assert body["subtotal"] == 3000
        assert body["total"] == 2500

    def test_apply_coupon_one_yen_above_min_purchase(
        self, client, auth_headers, make_product, fixed_coupon
    ):
        """CPN-06 割引対象額が最低購入金額より1円多ければ、クーポンを適用できる。"""
        product = make_product(price=3001)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "FLAT500"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 3001
        assert body["discount_amount"] == 500
        assert body["subtotal"] == 3001
        assert body["total"] == 2501


class TestMaxDiscountAmountBoundary:
    def test_percentage_discount_one_yen_below_max_is_applied_as_is(
        self, client, auth_headers, make_product, sample_coupon
    ):
        """CPN-07 定率の割引額が割引上限額より1円少ないときは、そのまま割引される。"""
        product = make_product(price=9990)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 9990
        assert body["discount_amount"] == 999
        assert body["subtotal"] == 9990
        assert body["total"] == 8991

    def test_percentage_discount_at_exact_max_is_applied_as_is(
        self, client, auth_headers, make_product, sample_coupon
    ):
        """CPN-08 定率の割引額が割引上限額ちょうどなら、そのまま割引される。"""
        product = make_product(price=10000)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 10000
        assert body["discount_amount"] == 1000
        assert body["subtotal"] == 10000
        assert body["total"] == 9000

    def test_percentage_discount_one_yen_above_max_is_capped(
        self, client, auth_headers, make_product, sample_coupon
    ):
        """CPN-09 定率の割引額が割引上限額を1円超えるときは、上限額で止まる。"""
        product = make_product(price=10010)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 10010
        assert body["discount_amount"] == 1000
        assert body["subtotal"] == 10010
        assert body["total"] == 9010


class TestPercentageDiscountRounding:
    def test_percentage_discount_fraction_is_truncated(
        self, client, auth_headers, make_product, sample_coupon
    ):
        """CPN-10 定率の割引額に円未満の端数が出るときは、切り捨てる。"""
        product = make_product(price=5007)
        client.post(
            "/cart/items",
            json={"product_id": product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 5007
        assert body["discount_amount"] == 500
        assert body["subtotal"] == 5007
        assert body["total"] == 4507


class TestUsageLimitBoundary:
    def test_apply_coupon_one_use_below_usage_limit(
        self, client, auth_headers, cart_with_items, make_coupon
    ):
        """CPN-11 使われた回数が発行数の上限より1回少なければ、クーポンを適用できる。"""
        make_coupon(code="LIMIT5", type="fixed", value=500, usage_limit=5, used_count=4)

        response = client.post(
            "/cart/coupon", json={"coupon_code": "LIMIT5"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 500
        assert body["subtotal"] == 4000
        assert body["total"] == 3500

    def test_apply_coupon_rejected_at_usage_limit(
        self, client, auth_headers, cart_with_items, make_coupon
    ):
        """CPN-12 使われた回数が発行数の上限ちょうどなら、クーポンを適用できない。"""
        make_coupon(code="LIMIT5", type="fixed", value=500, usage_limit=5, used_count=5)

        response = client.post(
            "/cart/coupon", json={"coupon_code": "LIMIT5"}, headers=auth_headers
        )

        assert response.status_code == 409

    def test_apply_coupon_rejected_above_usage_limit(
        self, client, auth_headers, cart_with_items, make_coupon
    ):
        """CPN-13 使われた回数が発行数の上限を1回超えていても、クーポンを適用できない。"""
        # 暫定：上限を超えた状態は基本設計書で起こりえないことになっており、
        # そのときの応答は書かれていない。「上限に達している」は「上限以上」と読むのが自然で、
        # 10章の409の行がそのまま当てはまるため、409を暫定値にしている（試験観点シート CPN-13）。
        # APIからは作れない状態なので、データで用意する。
        make_coupon(code="LIMIT5", type="fixed", value=500, usage_limit=5, used_count=6)

        response = client.post(
            "/cart/coupon", json={"coupon_code": "LIMIT5"}, headers=auth_headers
        )

        assert response.status_code == 409


class TestUnlimitedUsageCoupon:
    def test_apply_unlimited_coupon_even_if_used_many_times(
        self, client, auth_headers, cart_with_items, make_coupon
    ):
        """CPN-14 発行数の上限が設定されていない（null）クーポンは、多く使われていても適用できる。"""
        make_coupon(
            code="WELCOME5",
            type="percentage",
            value=5,
            usage_limit=None,
            used_count=1000,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "WELCOME5"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["coupon_code"] == "WELCOME5"
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 200
        assert body["subtotal"] == 4000
        assert body["total"] == 3800

    def test_checkout_with_unlimited_coupon_increments_used_count(
        self, client, auth_headers, db_session, cart_with_items, make_coupon
    ):
        """CPN-15 発行数の上限が設定されていない（null）クーポンでも注文を確定でき、used_count は1増える。"""
        coupon = make_coupon(
            code="WELCOME5",
            type="percentage",
            value=5,
            usage_limit=None,
            used_count=1000,
        )
        applied = client.post(
            "/cart/coupon", json={"coupon_code": "WELCOME5"}, headers=auth_headers
        )
        assert applied.status_code == 200  # 前提の適用が通っていることを先に確かめる

        response = client.post(
            "/orders", json={"expected_total": 3800}, headers=auth_headers
        )

        assert response.status_code == 201
        body = response.json()
        assert body["status"] == "confirmed"
        assert body["subtotal"] == 4000
        assert body["coupon_code"] == "WELCOME5"
        assert body["discount_amount"] == 200

        # used_count はどのAPIからも見えないため、DBで見る
        db_session.refresh(coupon)
        assert coupon.used_count == 1001
        assert coupon.usage_limit is None


class TestEligibleSubtotal:
    def test_sale_items_are_excluded_from_eligible_subtotal(
        self, client, auth_headers, cart_with_items, sale_product, sample_coupon
    ):
        """CPN-16 セール品を含むカートでは、セール品を除いた金額が割引対象額になり、割引額はそこから求める。"""
        client.post(
            "/cart/items",
            json={"product_id": sale_product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 400
        assert body["subtotal"] == 6000
        assert body["total"] == 5600

    def test_apply_coupon_rejected_when_all_items_are_on_sale(
        self, client, auth_headers, sale_product, sample_coupon
    ):
        """CPN-17 全部がセール品のカートでは、小計が最低購入金額以上でも割引対象額は0円なので、クーポンを適用できない。"""
        client.post(
            "/cart/items",
            json={"product_id": sale_product.id, "quantity": 2},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )

        assert response.status_code == 422

    def test_excluded_category_items_are_excluded_from_eligible_subtotal(
        self, client, auth_headers, cart_with_items, make_product, make_coupon
    ):
        """CPN-18 クーポンの対象外カテゴリの商品は、割引対象額から除かれる。"""
        accessory = make_product(price=1000, category="accessories")
        client.post(
            "/cart/items",
            json={"product_id": accessory.id, "quantity": 1},
            headers=auth_headers,
        )
        make_coupon(
            code="NOACC15",
            type="percentage",
            value=15,
            min_purchase_amount=3000,
            excluded_categories=["accessories"],
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "NOACC15"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 600
        assert body["subtotal"] == 5000
        assert body["total"] == 4400


class TestValidityPeriodBoundary:
    # CPN-20（終了日時ちょうど）は確認方法が「対象外」のため、テストにしない。

    def test_apply_coupon_just_before_valid_to(
        self, client, auth_headers, db_session, cart_with_items, fixed_coupon
    ):
        """CPN-19 終了日時の直前なら、クーポンを適用できる。"""
        fixed_coupon.valid_to = utcnow() + timedelta(minutes=1)
        db_session.commit()

        response = client.post(
            "/cart/coupon", json={"coupon_code": "FLAT500"}, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["eligible_subtotal"] == 4000
        assert body["discount_amount"] == 500
        assert body["subtotal"] == 4000
        assert body["total"] == 3500

    def test_apply_coupon_rejected_after_valid_to(
        self, client, auth_headers, db_session, cart_with_items, fixed_coupon
    ):
        """CPN-21 終了日時を過ぎたら、クーポンを適用できない。"""
        fixed_coupon.valid_to = utcnow() - timedelta(minutes=1)
        db_session.commit()

        response = client.post(
            "/cart/coupon", json={"coupon_code": "FLAT500"}, headers=auth_headers
        )

        assert response.status_code == 422


class TestApplyCouponFailure:
    @pytest.mark.skip(
        reason="未決：発行数の上限と有効期限外に同時に当てはまるとき、409と422のどちらを返すかを基本設計書10章が定めていない"
    )
    def test_apply_coupon_rejected_when_both_usage_limit_and_validity_fail(
        self, client, auth_headers, cart_with_items, make_coupon
    ):
        """CPN-22 クーポンが使えない条件の2つ（発行数の上限・有効期間）に同時に当てはまると、クーポンを適用できない。"""
        make_coupon(
            code="BOTHNG",
            type="fixed",
            value=500,
            usage_limit=5,
            used_count=5,
            valid_from_days=-60,
            valid_to_days=-30,
        )

        response = client.post(
            "/cart/coupon", json={"coupon_code": "BOTHNG"}, headers=auth_headers
        )

        # 期待ステータスが決まったら、どちらか一方に絞る
        assert response.status_code in (409, 422)

    def test_failed_apply_keeps_previously_applied_coupon(
        self, client, auth_headers, cart_with_items, sample_coupon, expired_coupon
    ):
        """CPN-23 適用中のクーポンがあるときに別のクーポンの適用に失敗しても、もとのクーポンは外れない。"""
        # 暫定：失敗した適用のあとのカートの状態は基本設計書に書かれていない。
        # 7章でカートに記録するのは「使える」場合だけなので、もとのクーポンが残ることを
        # 暫定値にしている（試験観点シート CPN-23）。
        client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )
        failed = client.post(
            "/cart/coupon", json={"coupon_code": "EXPIRED20"}, headers=auth_headers
        )
        assert failed.status_code == 422

        response = client.get("/cart", headers=auth_headers)

        assert response.status_code == 200
        body = response.json()
        assert body["applied_coupon_code"] == "SPRING10"
        assert body["discount_amount"] == 400
        assert body["subtotal"] == 4000
        assert body["total"] == 3600


class TestCheckoutWithCoupon:
    def test_checkout_with_coupon_records_coupon_and_discount(
        self, client, auth_headers, cart_with_items, sample_coupon
    ):
        """CPN-03 クーポンを適用したカートで注文を確定すると、クーポンと割引額が注文に写し取られる。"""
        applied = client.post(
            "/cart/coupon", json={"coupon_code": "SPRING10"}, headers=auth_headers
        )
        assert applied.status_code == 200  # 前提の適用が通っていることを先に確かめる

        response = client.post(
            "/orders", json={"expected_total": 3600}, headers=auth_headers
        )

        assert response.status_code == 201
        body = response.json()
        assert body["status"] == "confirmed"
        assert body["subtotal"] == 4000
        assert body["coupon_code"] == "SPRING10"
        assert body["discount_amount"] == 400
        assert len(body["items"]) == 1
        item = body["items"][0]
        assert item["unit_price"] == 1000
        assert item["quantity"] == 4


class TestRegression:
    def test_checkout_without_coupon_has_no_coupon_and_zero_discount(
        self, client, auth_headers, sample_product
    ):
        """ORD-01 回帰 クーポンを使わずに注文を確定すると、coupon_code は null、discount_amount は0になる。"""
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 2},
            headers=auth_headers,
        )

        response = client.post("/orders", headers=auth_headers)

        assert response.status_code == 201
        body = response.json()
        assert body["subtotal"] == 2000
        assert body["status"] == "confirmed"
        assert body["coupon_code"] is None
        assert body["discount_amount"] == 0
