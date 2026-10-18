import importlib

import pytest

from app import auth


class TestAuthEnvironmentFallback:
    def test_secret_key_falls_back_to_insecure_default_when_unset(
        self, monkeypatch, capsys
    ):
        # .env に JWT_SECRET_KEY が実際に設定されているため、reload時の
        # load_dotenv() 呼び出しで値が復元されないよう no-op に差し替える。
        monkeypatch.setattr("dotenv.load_dotenv", lambda *a, **k: None)
        monkeypatch.delenv("JWT_SECRET_KEY", raising=False)
        importlib.reload(auth)

        assert auth.SECRET_KEY == "insecure-default-secret"
        out = capsys.readouterr().out
        assert "JWT_SECRET_KEY が未設定です" in out

    def test_secret_key_uses_env_value_when_set(self, monkeypatch):
        monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-value")
        importlib.reload(auth)

        assert auth.SECRET_KEY == "test-secret-value"

    def test_algorithm_defaults_to_hs256_when_unset(self, monkeypatch):
        monkeypatch.delenv("JWT_ALGORITHM", raising=False)
        importlib.reload(auth)

        assert auth.ALGORITHM == "HS256"

    def test_expire_minutes_defaults_to_60_when_unset(self, monkeypatch):
        monkeypatch.delenv("JWT_EXPIRE_MINUTES", raising=False)
        importlib.reload(auth)

        assert auth.EXPIRE_MINUTES == 60

    def test_expire_minutes_uses_env_value_when_set(self, monkeypatch):
        monkeypatch.setenv("JWT_EXPIRE_MINUTES", "15")
        importlib.reload(auth)

        assert auth.EXPIRE_MINUTES == 15


@pytest.fixture(scope="module", autouse=True)
def _restore_auth_module_after_module():
    yield
    importlib.reload(auth)
