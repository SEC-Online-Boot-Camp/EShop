class TestListProducts:
    def test_list_products_returns_registered_product(self, client, sample_product):
        response = client.get("/products")

        assert response.status_code == 200
        body = response.json()
        target = next(p for p in body if p["id"] == sample_product.id)
        assert target["name"] == sample_product.name
        assert target["price"] == sample_product.price
        assert target["category"] == sample_product.category
        assert target["is_sale"] == sample_product.is_sale
