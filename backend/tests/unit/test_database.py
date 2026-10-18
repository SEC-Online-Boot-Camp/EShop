import importlib
from unittest.mock import MagicMock, patch

import pytest

from app import database


def test_sqlite_url_uses_check_same_thread(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "sqlite:///./unit.db")

    with patch("sqlalchemy.create_engine") as mock_create_engine:
        importlib.reload(database)

    mock_create_engine.assert_called_once_with(
        "sqlite:///./unit.db", connect_args={"check_same_thread": False}
    )


def test_non_sqlite_url_does_not_pass_sqlite_connect_args(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/app")

    with patch("sqlalchemy.create_engine") as mock_create_engine:
        importlib.reload(database)

    mock_create_engine.assert_called_once_with(
        "postgresql://user:pass@localhost:5432/app"
    )


def test_default_url_is_sqlite_when_env_missing(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)

    with patch("sqlalchemy.create_engine") as mock_create_engine:
        importlib.reload(database)

    mock_create_engine.assert_called_once_with(
        "sqlite:///./ecommerce.db", connect_args={"check_same_thread": False}
    )


def test_get_db_closes_session_after_iteration(monkeypatch):
    fake_session = MagicMock()
    fake_factory = MagicMock(return_value=fake_session)
    monkeypatch.setattr(database, "SessionLocal", fake_factory)

    gen = database.get_db()
    yielded = next(gen)
    assert yielded is fake_session

    with pytest.raises(StopIteration):
        next(gen)

    fake_session.close.assert_called_once()


def test_get_db_closes_session_on_exception(monkeypatch):
    fake_session = MagicMock()
    fake_factory = MagicMock(return_value=fake_session)
    monkeypatch.setattr(database, "SessionLocal", fake_factory)

    gen = database.get_db()
    _ = next(gen)

    with pytest.raises(RuntimeError):
        gen.throw(RuntimeError("forced"))

    fake_session.close.assert_called_once()


@pytest.fixture(scope="module", autouse=True)
def _restore_database_module_after_module():
    yield
    importlib.reload(database)
