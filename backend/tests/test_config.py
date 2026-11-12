import pytest
from pydantic import ValidationError

from app.core.config import Settings

GOOD = "x7Gq2mV9pLr4TnB8wZ1cKd6sYf3HjA0e"


def _settings(key: str) -> Settings:
    return Settings(_env_file=None, database_url="postgresql+asyncpg://u:p@h/d", secret_key=key)


def test_strong_secret_key_is_accepted():
    assert _settings(GOOD).secret_key == GOOD


@pytest.mark.parametrize("bad", ["short", "change-me-to-a-long-random-string", "change-me", "A" * 31])
def test_weak_or_placeholder_secret_key_is_rejected(bad):
    with pytest.raises(ValidationError):
        _settings(bad)
