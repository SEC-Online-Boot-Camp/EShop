"""クーポンの適用可否判定と割引額の計算。

`/cart/coupon`（プレビュー）と `/orders`（確定時の再検証）の双方から呼び出す。
中身はまだ実装していない（関数の名前と引数・戻り値だけを決めてある）。utcnow 以外は、呼ぶと 501 を返す。
"""

from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models import Coupon


def _not_implemented():
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="未実装です"
    )


def utcnow() -> datetime:
    """DBに保存された日時（naive UTC）と比較できる現在時刻を返す。"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def find_coupon(db: Session, code: str) -> Coupon:
    _not_implemented()


def calc_eligible_subtotal(cart_items, coupon: Coupon) -> int:
    """割引の計算対象となる金額を求める。"""
    _not_implemented()


def calc_discount(coupon: Coupon, eligible_subtotal: int) -> int:
    """割引額を求める。"""
    _not_implemented()


def evaluate(db: Session, cart_items, code: str) -> tuple[Coupon, int, int]:
    """クーポンを検証し、(クーポン, 割引対象金額, 割引額) を返す。"""
    _not_implemented()


def consume(db: Session, code: str) -> bool:
    """発行数を1つ消費する。上限に達していて消費できなければ False を返す。"""
    _not_implemented()
