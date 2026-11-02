class TestAddItem:
    def test_add_item_success(self, client, auth_headers, sample_product):
        response = client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 2},
            headers=auth_headers,
        )

        assert response.status_code == 200
        body = response.json()
        assert body["subtotal"] == sample_product.price * 2
        assert body["items"][0]["quantity"] == 2

    def test_add_existing_item_increments_quantity(
        self, client, auth_headers, sample_product
    ):
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 2},
            headers=auth_headers,
        )

        body = response.json()
        assert len(body["items"]) == 1
        assert body["items"][0]["quantity"] == 3

    def test_add_item_unknown_product(self, client, auth_headers):
        response = client.post(
            "/cart/items",
            json={"product_id": 999, "quantity": 1},
            headers=auth_headers,
        )

        assert response.status_code == 404
        assert response.json()["detail"] == "商品が見つかりません"

    def test_add_item_without_login(self, client, sample_product):
        response = client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 1},
        )

        assert response.status_code == 401

    def test_add_item_negative_quantity_is_rejected(
        self, client, auth_headers, sample_product
    ):
        """回帰テスト：4者レビューで見つかった負数数量の受け入れ(C-1)を防げているか確認する"""
        response = client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": -5},
            headers=auth_headers,
        )

        assert response.status_code == 422


class TestGetCart:
    def test_get_cart_without_login(self, client):
        response = client.get("/cart")

        assert response.status_code == 401

    def test_get_empty_cart(self, client, auth_headers):
        response = client.get("/cart", headers=auth_headers)

        assert response.status_code == 200
        assert response.json() == {
            "items": [],
            "subtotal": 0,
            "applied_coupon_code": None,
            "discount_amount": 0,
            "total": 0,
        }


class TestCartUserIsolation:
    def test_other_users_items_do_not_appear_in_my_cart(
        self, client, auth_headers, other_auth_headers, sample_product
    ):
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 3},
            headers=other_auth_headers,
        )

        response = client.get("/cart", headers=auth_headers)

        assert response.status_code == 200
        assert response.json() == {
            "items": [],
            "subtotal": 0,
            "applied_coupon_code": None,
            "discount_amount": 0,
            "total": 0,
        }
