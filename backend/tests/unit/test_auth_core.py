from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from jose import jwt

from app import auth
from app.models import User


class TestAuthCore:
    def test_hash_and_verify_password(self):
        plain = "password123"
        hashed = auth.hash_password(plain)
        assert hashed != plain
        assert auth.verify_password(plain, hashed)

    def test_create_access_token_contains_subject_and_exp(self):
        token = auth.create_access_token("user@example.com")
        payload = jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
        assert payload["sub"] == "user@example.com"
        assert "exp" in payload

    def test_get_current_user_rejects_invalid_token(self):
        db = MagicMock()
        with pytest.raises(HTTPException) as exc:
            auth.get_current_user(token="invalid-token", db=db)
        assert exc.value.status_code == 401

    def test_get_current_user_rejects_when_user_not_found(self):
        token = auth.create_access_token("missing@example.com")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None

        with pytest.raises(HTTPException) as exc:
            auth.get_current_user(token=token, db=db)

        assert exc.value.status_code == 401

    def test_get_current_user_returns_user(self):
        token = auth.create_access_token("found@example.com")
        db = MagicMock()
        user = User(email="found@example.com", hashed_password="dummy")
        db.query.return_value.filter.return_value.first.return_value = user

        got = auth.get_current_user(token=token, db=db)
        assert got is user

    def test_get_current_user_rejects_token_without_sub(self):
        token = jwt.encode(
            {"exp": datetime.now(timezone.utc).timestamp() + 60},
            auth.SECRET_KEY,
            algorithm=auth.ALGORITHM,
        )
        db = MagicMock()

        with pytest.raises(HTTPException) as exc:
            auth.get_current_user(token=token, db=db)

        assert exc.value.status_code == 401
