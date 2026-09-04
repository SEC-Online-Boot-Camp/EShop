from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.auth import hash_password
from app.coupon import utcnow
from app.database import Base, get_db
from app.main import app
from app.models import Coupon, Product, User

TEST_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture()
def sample_product(db_session):
    product = Product(name="テスト商品", price=1000, category="test", is_sale=False)
    db_session.add(product)
    db_session.commit()
    db_session.refresh(product)
    return product


@pytest.fixture()
def registered_user(db_session):
    user = User(email="test@example.com", hashed_password=hash_password("password123"))
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


@pytest.fixture()
def auth_headers(client, registered_user):
    response = client.post(
        "/auth/login",
        json={"email": registered_user.email, "password": "password123"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def other_user(db_session):
    user = User(email="other@example.com", hashed_password=hash_password("password123"))
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


@pytest.fixture()
def other_auth_headers(client, other_user):
    response = client.post(
        "/auth/login",
        json={"email": other_user.email, "password": "password123"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def make_product(db_session):
    """任意の商品を作るファクトリ。境界値のテストデータを組み立てるときに使う。"""

    def _make(price=1000, name="テスト商品", category="test", is_sale=False):
        product = Product(name=name, price=price, category=category, is_sale=is_sale)
        db_session.add(product)
        db_session.commit()
        db_session.refresh(product)
        return product

    return _make


@pytest.fixture()
def sale_product(make_product):
    return make_product(name="セール品", price=2000, category="test", is_sale=True)


@pytest.fixture()
def make_coupon(db_session):
    """任意のクーポンを作るファクトリ。"""

    def _make(
        code="TESTCODE",
        type="percentage",
        value=10,
        max_discount_amount=None,
        min_purchase_amount=0,
        excluded_categories=None,
        usage_limit=100,
        used_count=0,
        valid_from_days=-30,
        valid_to_days=30,
    ):
        now = utcnow()
        coupon = Coupon(
            code=code,
            type=type,
            value=value,
            max_discount_amount=max_discount_amount,
            min_purchase_amount=min_purchase_amount,
            excluded_categories=excluded_categories,
            usage_limit=usage_limit,
            used_count=used_count,
            valid_from=now + timedelta(days=valid_from_days),
            valid_to=now + timedelta(days=valid_to_days),
        )
        db_session.add(coupon)
        db_session.commit()
        db_session.refresh(coupon)
        return coupon

    return _make


@pytest.fixture()
def sample_coupon(make_coupon):
    """定率10%・割引上限1,000円・最低購入金額3,000円のクーポン。"""
    return make_coupon(
        code="SPRING10",
        type="percentage",
        value=10,
        max_discount_amount=1000,
        min_purchase_amount=3000,
    )


@pytest.fixture()
def fixed_coupon(make_coupon):
    """定額500円引き・最低購入金額3,000円のクーポン。"""
    return make_coupon(
        code="FLAT500", type="fixed", value=500, min_purchase_amount=3000
    )


@pytest.fixture()
def unlimited_coupon(make_coupon):
    """発行数上限のない（usage_limit が NULL の）クーポン。"""
    return make_coupon(code="WELCOME5", type="percentage", value=5, usage_limit=None)


@pytest.fixture()
def exhausted_coupon(make_coupon):
    """発行数上限に達しているクーポン。"""
    return make_coupon(
        code="SOLDOUT", type="fixed", value=1000, usage_limit=1, used_count=1
    )


@pytest.fixture()
def expired_coupon(make_coupon):
    """有効期限が切れているクーポン。"""
    return make_coupon(
        code="EXPIRED20",
        type="percentage",
        value=20,
        valid_from_days=-60,
        valid_to_days=-30,
    )


@pytest.fixture()
def cart_with_items(client, auth_headers, sample_product):
    """sample_product を4点入れた小計4,000円のカート。"""
    client.post(
        "/cart/items",
        json={"product_id": sample_product.id, "quantity": 4},
        headers=auth_headers,
    )
    return sample_product
