import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import get_settings
from app.models import Base

target_metadata = Base.metadata


def _include_object(obj, name, type_, reflected, compare_to):
    # Only manage tables we define; PostGIS extension tables must never be touched.
    if type_ == "table":
        return name in target_metadata.tables
    table = getattr(obj, "table", None)
    if reflected and table is not None:
        return table.name in target_metadata.tables
    return True


def _run(connection):
    context.configure(
        connection=connection, target_metadata=target_metadata, include_object=_include_object
    )
    with context.begin_transaction():
        context.run_migrations()


async def _run_async():
    engine = create_async_engine(get_settings().database_url)
    async with engine.connect() as connection:
        await connection.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    raise SystemExit("offline mode not supported")
asyncio.run(_run_async())
