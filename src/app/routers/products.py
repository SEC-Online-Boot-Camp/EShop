from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from src.app.database import get_db
from src.app.models import Product
from src.app.schemas import ProductOut

router = APIRouter(prefix="/products", tags=["products"])


@router.get("", response_model=list[ProductOut])
def list_products(db: Session = Depends(get_db)):
    return db.query(Product).all()
