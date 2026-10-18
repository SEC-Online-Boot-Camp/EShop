class TestCheckout:
    def test_checkout_success(self, client, auth_headers, sample_product):
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 2},
            headers=auth_headers,
        )

        response = client.post("/orders", headers=auth_headers)

        assert response.status_code == 201
        body = response.json()
        assert body["subtotal"] == sample_product.price * 2
        assert body["status"] == "confirmed"
        assert len(body["items"]) == 1
        item = body["items"][0]
        assert item["product_id"] == sample_product.id
        assert item["product_name"] == sample_product.name
        assert item["unit_price"] == sample_product.price
        assert item["quantity"] == 2

    def test_checkout_without_login(self, client):
        response = client.post("/orders")
        assert response.status_code == 401

    def test_checkout_with_empty_cart(self, client, auth_headers):
        response = client.post("/orders", headers=auth_headers)
        assert response.status_code == 400
        assert response.json()["detail"] == "カートが空です"

    def test_cart_is_cleared_after_checkout(self, client, auth_headers, sample_product):
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 1},
            headers=auth_headers,
        )
        client.post("/orders", headers=auth_headers)

        response = client.get("/cart", headers=auth_headers)

        assert response.json()["items"] == []


class TestOrderUserIsolation:
    def test_checkout_only_includes_my_own_cart_items(
        self, client, auth_headers, other_auth_headers, sample_product
    ):
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 5},
            headers=other_auth_headers,
        )
        client.post(
            "/cart/items",
            json={"product_id": sample_product.id, "quantity": 1},
            headers=auth_headers,
        )

        response = client.post("/orders", headers=auth_headers)

        assert response.status_code == 201
        body = response.json()
        assert len(body["items"]) == 1
        assert body["items"][0]["quantity"] == 1
        assert body["subtotal"] == sample_product.price
