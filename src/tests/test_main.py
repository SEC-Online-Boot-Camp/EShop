from fastapi.testclient import TestClient

from src.app.main import app


def test_health_check_returns_ok():
    with TestClient(app) as client:
        res = client.get("/")

    assert res.status_code == 200
    assert res.json() == {"status": "ok"}
