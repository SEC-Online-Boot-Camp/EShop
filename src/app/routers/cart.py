from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app import coupon as coupon_service
from app.auth import get_current_user
from app.database import get_db
from app.models import Cart, CartItem, Product, User
from app.schemas import (
    CartItemCreate,
    CartItemOut,
    CartOut,
    CouponApplyOut,
    CouponApplyRequest,
)

router = APIRouter(prefix="/cart", tags=["cart"])


@router.post("/items", response_model=CartOut)
def add_item(
    payload: CartItemCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    product = db.query(Product).filter(Product.id == payload.product_id).first()
    if product is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="商品が見つかりません"
        )

    existing = (
        db.query(CartItem)
        .filter(
            CartItem.user_id == current_user.id,
            CartItem.product_id == payload.product_id,
        )
        .first()
    )
    if existing:
        existing.quantity += payload.quantity
    else:
        db.add(
            CartItem(
                user_id=current_user.id,
                product_id=payload.product_id,
                quantity=payload.quantity,
            )
        )
    db.commit()

    return _build_cart_out(db, current_user)


@router.get("", response_model=CartOut)
def get_cart(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _build_cart_out(db, current_user)


@router.post("/coupon", response_model=CouponApplyOut)
def apply_coupon(
    payload: CouponApplyRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """クーポンをカートに適用し、割引後金額をプレビューする。

    ここでは発行数の消費（used_count の加算）は行わない。消費は注文確定時。
    """
    cart_items = _get_cart_items(db, current_user)
    _, eligible_subtotal, discount = coupon_service.evaluate(
        db, cart_items, payload.coupon_code
    )

    cart = _get_or_create_cart(db, current_user)
    cart.applied_coupon_code = payload.coupon_code
    db.commit()

    subtotal = _calc_subtotal(cart_items)
    return CouponApplyOut(
        coupon_code=payload.coupon_code,
        eligible_subtotal=eligible_subtotal,
        discount_amount=discount,
        subtotal=subtotal,
        total=subtotal - discount,
    )


@router.delete("/coupon", response_model=CartOut)
def remove_coupon(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cart = _get_or_create_cart(db, current_user)
    cart.applied_coupon_code = None
    db.commit()
    return _build_cart_out(db, current_user)


def _get_cart_items(db: Session, user: User) -> list[CartItem]:
    return db.query(CartItem).filter(CartItem.user_id == user.id).all()


def _get_or_create_cart(db: Session, user: User) -> Cart:
    cart = db.query(Cart).filter(Cart.user_id == user.id).first()
    if cart is None:
        cart = Cart(user_id=user.id)
        db.add(cart)
        db.flush()
    return cart


def _calc_subtotal(cart_items: list[CartItem]) -> int:
    return sum(item.product.price * item.quantity for item in cart_items)


def _build_cart_out(db: Session, user: User) -> CartOut:
    cart_items = _get_cart_items(db, user)
    items = [
        CartItemOut(
            product_id=item.product.id,
            product_name=item.product.name,
            unit_price=item.product.price,
            quantity=item.quantity,
        )
        for item in cart_items
    ]
    subtotal = sum(item.unit_price * item.quantity for item in items)

    cart = db.query(Cart).filter(Cart.user_id == user.id).first()
    applied_code = cart.applied_coupon_code if cart else None
    discount = 0
    if applied_code is not None:
        try:
            _, _, discount = coupon_service.evaluate(db, cart_items, applied_code)
        except HTTPException:
            # 適用後にカート内容や在庫状況が変わり、条件を満たさなくなった場合は
            # 割引なしの金額を返す。確定時（POST /orders）に改めて検証する。
            discount = 0

    return CartOut(
        items=items,
        subtotal=subtotal,
        applied_coupon_code=applied_code,
        discount_amount=discount,
        total=subtotal - discount,
    )
