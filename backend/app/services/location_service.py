import json
import uuid
from datetime import UTC, datetime

from redis.asyncio import Redis
from sqlalchemy import delete, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.location import DriverLocation

LOCATION_TTL_SECONDS = 30


def location_key(driver_id: uuid.UUID | str) -> str:
    return f"driver:location:{driver_id}"


async def clear_location(session: AsyncSession, redis: Redis, driver_id: uuid.UUID) -> None:
    """Forget a driver's live position (used when they go offline, are rejected or suspended)."""
    await redis.delete(location_key(driver_id))
    await session.execute(delete(DriverLocation).where(DriverLocation.driver_id == driver_id))


async def record_location(
    session: AsyncSession,
    redis: Redis,
    driver_id: uuid.UUID,
    latitude: float,
    longitude: float,
    heading: float | None,
    speed: float | None,
    accuracy: float | None,
) -> None:
    """Store the driver's latest position: Redis (freshness, expires) and PostGIS (spatial queries)."""
    now = datetime.now(UTC)
    # ST_MakePoint takes longitude first, then latitude.
    await session.execute(
        text(
            """
            INSERT INTO driver_locations (driver_id, location, heading, speed, accuracy, recorded_at)
            VALUES (:d, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :h, :s, :a, :t)
            ON CONFLICT (driver_id) DO UPDATE SET
              location = EXCLUDED.location, heading = EXCLUDED.heading, speed = EXCLUDED.speed,
              accuracy = EXCLUDED.accuracy, recorded_at = EXCLUDED.recorded_at
            """
        ),
        {"d": driver_id, "lat": latitude, "lng": longitude, "h": heading, "s": speed, "a": accuracy, "t": now},
    )
    await session.commit()
    await redis.set(
        location_key(driver_id),
        json.dumps({"latitude": latitude, "longitude": longitude, "heading": heading, "speed": speed,
                    "accuracy": accuracy, "recorded_at": now.isoformat()}),
        ex=LOCATION_TTL_SECONDS,
    )
