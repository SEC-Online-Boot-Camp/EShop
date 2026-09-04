"""初期データ投入スクリプト。

使い方: python -m app.seed
"""

from app.auth import hash_password
from app.database import Base, SessionLocal, engine
from app.models import Product, User


def seed():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        if db.query(User).first() is not None:
            print("すでにデータが投入されています。スキップします。")
            return

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
        db.add_all(users + products)
        db.commit()
        print(f"ユーザー{len(users)}件・商品{len(products)}件を投入しました。")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
