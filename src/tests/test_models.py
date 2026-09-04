import pytest
from sqlalchemy import inspect as sa_inspect

from src.app.models import CartItem, Order, OrderItem, Product, User


class TestModelDefinitions:
    def test_table_names(self):
        assert User.__tablename__ == "users"
        assert Product.__tablename__ == "products"
        assert CartItem.__tablename__ == "cart_items"
        assert Order.__tablename__ == "orders"
        assert OrderItem.__tablename__ == "order_items"

    def test_column_defaults(self):
        assert User.__table__.c.member_rank.default.arg == "general"
        assert Product.__table__.c.is_sale.default.arg is False
        assert CartItem.__table__.c.quantity.default.arg == 1
        assert Order.__table__.c.status.default.arg == "confirmed"
        assert callable(Order.__table__.c.created_at.default.arg)

    def test_non_nullable_columns(self):
        assert User.__table__.c.email.nullable is False
        assert User.__table__.c.hashed_password.nullable is False
        assert Product.__table__.c.name.nullable is False
        assert Product.__table__.c.price.nullable is False
        assert Product.__table__.c.category.nullable is False
        assert CartItem.__table__.c.user_id.nullable is False
        assert CartItem.__table__.c.product_id.nullable is False
        assert Order.__table__.c.user_id.nullable is False
        assert Order.__table__.c.subtotal.nullable is False
        assert OrderItem.__table__.c.order_id.nullable is False
        assert OrderItem.__table__.c.product_id.nullable is False
        assert OrderItem.__table__.c.product_name.nullable is False
        assert OrderItem.__table__.c.unit_price.nullable is False
        assert OrderItem.__table__.c.quantity.nullable is False

    def test_foreign_keys(self):
        assert (
            str(next(iter(CartItem.__table__.c.user_id.foreign_keys)).target_fullname)
            == "users.id"
        )
        assert (
            str(
                next(iter(CartItem.__table__.c.product_id.foreign_keys)).target_fullname
            )
            == "products.id"
        )
        assert (
            str(next(iter(Order.__table__.c.user_id.foreign_keys)).target_fullname)
            == "users.id"
        )
        assert (
            str(next(iter(OrderItem.__table__.c.order_id.foreign_keys)).target_fullname)
            == "orders.id"
        )
        assert (
            str(
                next(
                    iter(OrderItem.__table__.c.product_id.foreign_keys)
                ).target_fullname
            )
            == "products.id"
        )

    def test_relationship_mappings(self):
        user_rel = sa_inspect(User).relationships
        cart_rel = sa_inspect(CartItem).relationships
        order_rel = sa_inspect(Order).relationships
        order_item_rel = sa_inspect(OrderItem).relationships

        assert user_rel["cart_items"].mapper.class_ is CartItem
        assert user_rel["orders"].mapper.class_ is Order
        assert cart_rel["user"].mapper.class_ is User
        assert cart_rel["product"].mapper.class_ is Product
        assert order_rel["user"].mapper.class_ is User
        assert order_rel["items"].mapper.class_ is OrderItem
        assert order_item_rel["order"].mapper.class_ is Order


class TestModelBehavior:
    def test_user_email_unique_constraint_is_enforced(self, db_session):
        from sqlalchemy.exc import IntegrityError

        db_session.add(User(email="dup@example.com", hashed_password="x"))
        db_session.commit()

        db_session.add(User(email="dup@example.com", hashed_password="y"))
        with pytest.raises(IntegrityError):
            db_session.commit()
        db_session.rollback()

    def test_appending_to_user_cart_items_relationship_persists(
        self, db_session, registered_user, sample_product
    ):
        registered_user.cart_items.append(
            CartItem(product_id=sample_product.id, quantity=2)
        )
        db_session.commit()

        reloaded = (
            db_session.query(CartItem)
            .filter(CartItem.user_id == registered_user.id)
            .all()
        )
        assert len(reloaded) == 1
        assert reloaded[0].quantity == 2
