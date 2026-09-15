import app.seed as seed_module
from app.models import Coupon, Product, User


class TestSeed:
    def test_seed_inserts_initial_data(self, db_session, monkeypatch, capsys):
        monkeypatch.setattr(seed_module, "SessionLocal", lambda: db_session)
        monkeypatch.setattr(seed_module, "hash_password", lambda _: "hashed-password")

        seed_module.seed()

        assert db_session.query(User).count() == 2
        assert db_session.query(Product).count() == 5

        users = {u.email: u.member_rank for u in db_session.query(User).all()}
        assert users["taro@example.com"] == "general"
        assert users["hanako@example.com"] == "gold"
        assert db_session.query(Coupon).count() == 6

        out = capsys.readouterr().out
        assert "ユーザー2件・商品5件・クーポン6件を投入しました。" in out

    def test_seed_is_idempotent_when_data_already_exists(
        self, db_session, monkeypatch, capsys
    ):
        monkeypatch.setattr(seed_module, "SessionLocal", lambda: db_session)
        monkeypatch.setattr(seed_module, "hash_password", lambda _: "hashed-password")

        seed_module.seed()
        capsys.readouterr()

        seed_module.seed()

        assert db_session.query(User).count() == 2
        assert db_session.query(Product).count() == 5

        out = capsys.readouterr().out
        assert "すでにデータが投入されています。スキップします。" in out

    def test_seed_adds_coupons_to_an_existing_database(
        self, db_session, monkeypatch, capsys
    ):
        """No.1・No.2で作ったDB（クーポン未投入）に対しても、クーポンだけは投入される。"""
        monkeypatch.setattr(seed_module, "SessionLocal", lambda: db_session)
        monkeypatch.setattr(seed_module, "hash_password", lambda _: "hashed-password")
        db_session.add(User(email="taro@example.com", hashed_password="hashed"))
        db_session.commit()

        seed_module.seed()

        assert db_session.query(User).count() == 1
        assert db_session.query(Coupon).count() == 6

        out = capsys.readouterr().out
        assert "クーポン6件を投入しました。" in out

    def test_seed_inserts_specific_products(self, db_session, monkeypatch):
        """Verify that products have specific names, prices, categories, and sale status."""
        monkeypatch.setattr(seed_module, "SessionLocal", lambda: db_session)
        monkeypatch.setattr(seed_module, "hash_password", lambda _: "hashed-password")

        seed_module.seed()

        # Fetch all products by insertion order (ID)
        products = db_session.query(Product).order_by(Product.id).all()
        assert len(products) == 5

        expected_products = [
            ("ワイヤレスマウス", 2980, "electronics", False),
            ("メカニカルキーボード", 12800, "electronics", False),
            ("モバイルバッテリー", 3480, "electronics", True),
            ("ノートPCスタンド", 4980, "accessories", False),
            ("USB-Cハブ", 5980, "accessories", True),
        ]

        for product, (name, price, category, is_sale) in zip(
            products, expected_products
        ):
            assert product.name == name
            assert product.price == price
            assert product.category == category
            assert product.is_sale == is_sale

    def test_seed_inserts_users_with_correct_email_and_rank(
        self, db_session, monkeypatch
    ):
        """Verify that users have specific emails and member ranks."""
        monkeypatch.setattr(seed_module, "SessionLocal", lambda: db_session)
        monkeypatch.setattr(seed_module, "hash_password", lambda _: "hashed-password")

        seed_module.seed()

        users = db_session.query(User).order_by(User.id).all()
        assert len(users) == 2

        assert users[0].email == "taro@example.com"
        assert users[0].member_rank == "general"
        assert users[1].email == "hanako@example.com"
        assert users[1].member_rank == "gold"
