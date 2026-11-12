import os
import subprocess
import sys
from pathlib import Path

import asyncpg
import pytest
import pytest_asyncio

BACKEND = Path(__file__).resolve().parent.parent


def _env_password() -> str:
    env = BACKEND.parent / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("DB_PASSWORD="):
                return line.split("=", 1)[1].strip()
    return os.environ.get("DB_PASSWORD", "devpass")


DB_HOST = os.environ.get("TEST_DB_HOST", "127.0.0.1")
DB_PORT = os.environ.get("TEST_DB_PORT", "5433")
PASSWORD = _env_password()
TEST_DB = "ride_freely_test"
TEST_URL = f"postgresql+asyncpg://app_user:{PASSWORD}@{DB_HOST}:{DB_PORT}/{TEST_DB}"

# Must be set before the app is imported anywhere.
os.environ["DATABASE_URL"] = TEST_URL
os.environ["SECRET_KEY"] = "test-secret-key-test-secret-key-0123456789"
os.environ.setdefault("REDIS_URL", "redis://127.0.0.1:6379/0")


@pytest.fixture(scope="session", autouse=True)
def _migrated_test_database():
    import asyncio

    async def create_db():
        conn = await asyncpg.connect(
            user="app_user", password=PASSWORD, host=DB_HOST, port=int(DB_PORT), database="driver_booking"
        )
        try:
            exists = await conn.fetchval("SELECT 1 FROM pg_database WHERE datname=$1", TEST_DB)
            if not exists:
                await conn.execute(f'CREATE DATABASE "{TEST_DB}"')
        finally:
            await conn.close()

    asyncio.run(create_db())
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND,
        check=True,
        env={**os.environ},
    )


@pytest_asyncio.fixture
async def db_session():
    from app.core.database import SessionLocal, engine

    async with SessionLocal() as session:
        yield session
    async with engine.begin() as conn:
        await conn.exec_driver_sql(
            "TRUNCATE driver_profiles, customer_profiles, users RESTART IDENTITY CASCADE"
        )


@pytest_asyncio.fixture
async def client(db_session):
    from httpx import ASGITransport, AsyncClient

    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
