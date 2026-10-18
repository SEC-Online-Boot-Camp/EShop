"""クーポンの適用可否判定と割引額の計算。

`/cart/coupon`（プレビュー）と `/orders`（確定時の再検証）の双方から呼び出す。
"""

from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models import Coupon


def utcnow() -> datetime:
    """DBに保存された日時（naive UTC）と比較できる現在時刻を返す。"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def find_coupon(db: Session, code: str) -> Coupon:
    coupon = db.query(Coupon).filter(Coupon.code == code).first()
    if coupon is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="クーポンが見つかりません"
        )
    return coupon


def calc_eligible_subtotal(cart_items, coupon: Coupon) -> int:
    """割引の計算対象となる金額を求める。"""
    excluded = coupon.excluded_categories or []
    eligible = 0
    for item in cart_items:
        if item.product.category in excluded:
            continue
        eligible += item.product.price * item.quantity
    return eligible


def calc_discount(coupon: Coupon, eligible_subtotal: int) -> int:
    """割引額を求める。"""
    if coupon.type == "fixed":
        return min(coupon.value, eligible_subtotal)

    discount = round(eligible_subtotal * coupon.value / 100)
    if coupon.max_discount_amount is not None:
        discount = min(discount, coupon.max_discount_amount)
    return min(discount, eligible_subtotal)


def evaluate(db: Session, cart_items, code: str) -> tuple[Coupon, int, int]:
    """クーポンを検証し、(クーポン, 割引対象金額, 割引額) を返す。"""
    coupon = find_coupon(db, code)
    now = utcnow()
    if not (coupon.valid_from <= now < coupon.valid_to):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="クーポンの有効期限外です",
        )

    if coupon.used_count >= (coupon.usage_limit or 0):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="クーポンの発行数上限に達しています",
        )

    eligible_subtotal = calc_eligible_subtotal(cart_items, coupon)
    if eligible_subtotal <= coupon.min_purchase_amount:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="最低購入金額を満たしていません",
        )

    return coupon, eligible_subtotal, calc_discount(coupon, eligible_subtotal)


def consume(db: Session, code: str) -> bool:
    """発行数を1つ消費する。上限に達していて消費できなければ False を返す。"""
    result = db.execute(
        text(
            "UPDATE coupons SET used_count = used_count + 1 "
            "WHERE code = :code AND used_count < usage_limit"
        ),
        {"code": code},
    )
    return result.rowcount == 1
