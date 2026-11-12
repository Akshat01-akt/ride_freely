from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    secret_key: str
    access_token_minutes: int = 30
    refresh_token_days: int = 7

    @field_validator("secret_key")
    @classmethod
    def _secret_key_must_be_strong(cls, v: str) -> str:
        if len(v) < 32 or v.lower().startswith("change-me"):
            raise ValueError("SECRET_KEY must be at least 32 characters and not the example placeholder")
        return v


@lru_cache
def get_settings() -> Settings:
    return Settings()
