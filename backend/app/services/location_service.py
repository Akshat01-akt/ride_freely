import uuid

from redis.asyncio import Redis
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.location import DriverLocation

LOCATION_TTL_SECONDS = 30


def location_key(driver_id: uuid.UUID | str) -> str:
    return f"driver:location:{driver_id}"


async def clear_location(session: AsyncSession, redis: Redis, driver_id: uuid.UUID) -> None:
    """Forget a driver's live position (used when they go offline, are rejected or suspended)."""
    await redis.delete(location_key(driver_id))
    await session.execute(delete(DriverLocation).where(DriverLocation.driver_id == driver_id))
