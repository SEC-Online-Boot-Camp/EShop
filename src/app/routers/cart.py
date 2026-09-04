from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.database import get_db
from app.models import CartItem, Product, User
from app.schemas import CartItemCreate, CartItemOut, CartOut

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


def _build_cart_out(db: Session, user: User) -> CartOut:
    cart_items = db.query(CartItem).filter(CartItem.user_id == user.id).all()
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
    return CartOut(items=items, subtotal=subtotal)
