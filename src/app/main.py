from fastapi import FastAPI

from app.routers import auth, cart, orders, products

app = FastAPI(title="ECサイト スターターAPI")

app.include_router(auth.router)
app.include_router(products.router)
app.include_router(cart.router)
app.include_router(orders.router)


@app.get("/")
def health_check():
    return {"status": "ok"}
