"""初期データ投入スクリプト。

使い方: python -m app.seed
"""

from datetime import timedelta

from app.auth import hash_password
from app.coupon import utcnow
from app.database import Base, SessionLocal, engine
from app.models import Coupon, Product, User


def seed():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        users = [
            User(
                email="taro@example.com",
                hashed_password=hash_password("password123"),
                member_rank="general",
            ),
            User(
                email="hanako@example.com",
                hashed_password=hash_password("password123"),
                member_rank="gold",
            ),
        ]
        products = [
            Product(
                name="ワイヤレスマウス",
                price=2980,
                category="electronics",
                is_sale=False,
            ),
            Product(
                name="メカニカルキーボード",
                price=12800,
                category="electronics",
                is_sale=False,
            ),
            Product(
                name="モバイルバッテリー",
                price=3480,
                category="electronics",
                is_sale=True,
            ),
            Product(
                name="ノートPCスタンド",
                price=4980,
                category="accessories",
                is_sale=False,
            ),
            Product(name="USB-Cハブ", price=5980, category="accessories", is_sale=True),
        ]

        now = utcnow()
        coupons = [
            Coupon(
                code="SPRING10",
                type="percentage",
                value=10,
                max_discount_amount=1000,
                min_purchase_amount=3000,
                usage_limit=100,
                used_count=0,
                valid_from=now - timedelta(days=30),
                valid_to=now + timedelta(days=30),
            ),
            Coupon(
                code="FLAT500",
                type="fixed",
                value=500,
                min_purchase_amount=3000,
                usage_limit=100,
                used_count=0,
                valid_from=now - timedelta(days=30),
                valid_to=now + timedelta(days=30),
            ),
            Coupon(
                code="WELCOME5",
                type="percentage",
                value=5,
                min_purchase_amount=0,
                usage_limit=None,
                used_count=0,
                valid_from=now - timedelta(days=30),
                valid_to=now + timedelta(days=30),
            ),
            Coupon(
                code="NOACC15",
                type="percentage",
                value=15,
                min_purchase_amount=3000,
                excluded_categories=["accessories"],
                usage_limit=100,
                used_count=0,
                valid_from=now - timedelta(days=30),
                valid_to=now + timedelta(days=30),
            ),
            Coupon(
                code="SOLDOUT",
                type="fixed",
                value=1000,
                min_purchase_amount=0,
                usage_limit=1,
                used_count=1,
                valid_from=now - timedelta(days=30),
                valid_to=now + timedelta(days=30),
            ),
            Coupon(
                code="EXPIRED20",
                type="percentage",
                value=20,
                min_purchase_amount=0,
                usage_limit=100,
                used_count=0,
                valid_from=now - timedelta(days=60),
                valid_to=now - timedelta(days=30),
            ),
        ]
        # ユーザー・商品とクーポンは別々に判定する。No.1・No.2で作った
        # ecommerce.db がすでにある状態で src-add を適用しても、
        # クーポンだけは投入されるようにするため。
        created = []
        if db.query(User).first() is None:
            db.add_all(users + products)
            created.append(f"ユーザー{len(users)}件・商品{len(products)}件")
        if db.query(Coupon).first() is None:
            db.add_all(coupons)
            created.append(f"クーポン{len(coupons)}件")

        if not created:
            print("すでにデータが投入されています。スキップします。")
            return

        db.commit()
        print("・".join(created) + "を投入しました。")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
