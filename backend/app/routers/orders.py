from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app import coupon as coupon_service
from app.auth import get_current_user
from app.database import get_db
from app.models import Cart, CartItem, Order, OrderItem, User
from app.schemas import CheckoutRequest, OrderOut

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
def checkout(
    payload: CheckoutRequest | None = Body(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cart_items = db.query(CartItem).filter(CartItem.user_id == current_user.id).all()
    if not cart_items:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="カートが空です"
        )

    subtotal = sum(item.product.price * item.quantity for item in cart_items)

    cart = db.query(Cart).filter(Cart.user_id == current_user.id).first()
    applied_code = cart.applied_coupon_code if cart else None
    discount = 0

    if applied_code is not None:
        # 確定時に必ず再検証する（価格変動・失効・上限到達がプレビュー後に起こり得る）。
        _, _, discount = coupon_service.evaluate(db, cart_items, applied_code)

        expected_total = payload.expected_total if payload else None
        if expected_total is not None and expected_total != subtotal - discount:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="カート内容が変更されています。金額を確認してください",
            )

        if not coupon_service.consume(db, applied_code):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="クーポンの発行数上限に達しています",
            )

    order = Order(
        user_id=current_user.id,
        subtotal=subtotal,
        coupon_code=applied_code,
        discount_amount=discount,
        status="confirmed",
    )
    db.add(order)
    db.flush()

    for item in cart_items:
        db.add(
            OrderItem(
                order_id=order.id,
                product_id=item.product.id,
                product_name=item.product.name,
                unit_price=item.product.price,
                quantity=item.quantity,
            )
        )
        db.delete(item)

    if cart is not None:
        cart.applied_coupon_code = None

    db.commit()
    db.refresh(order)
    return order
