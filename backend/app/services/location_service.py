import json
import math
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


MAX_RESULTS = 50

# Customers choose the search point, so exact distances from several points would reveal a driver's position.
DISTANCE_STEP_METERS = 100


def _coarse(distance: float) -> float:
    return float(max(1, math.ceil(distance / DISTANCE_STEP_METERS)) * DISTANCE_STEP_METERS)


async def nearby_drivers(session: AsyncSession, redis: Redis, latitude: float, longitude: float, radius_m: float) -> list[dict]:
    """Verified, available drivers within [radius_m] metres, nearest first, whose live location is still fresh."""
    rows = (
        await session.execute(
            text(
                """
                WITH here AS (SELECT ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography AS p)
                SELECT dp.id, u.full_name, dp.hourly_rate, dp.rating, dp.experience_years,
                       ST_Distance(l.location, here.p) AS distance
                FROM here, driver_locations l
                JOIN driver_profiles dp ON dp.id = l.driver_id
                JOIN users u ON u.id = dp.user_id
                WHERE dp.verification_status = 'APPROVED' AND dp.availability_status = 'AVAILABLE'
                  AND u.is_active AND ST_DWithin(l.location, here.p, :radius)
                  AND l.recorded_at > now() - make_interval(secs => :fresh)
                ORDER BY distance
                LIMIT :limit
                """
            ),
            {"lat": latitude, "lng": longitude, "radius": radius_m, "limit": MAX_RESULTS, "fresh": LOCATION_TTL_SECONDS},
        )
    ).all()
    if not rows:
        return []
    fresh = await redis.mget([location_key(r.id) for r in rows])
    return [
        {
            "id": r.id,
            "name": r.full_name,
            "hourly_rate": str(r.hourly_rate),
            "rating": str(r.rating),
            "experience_years": r.experience_years,
            "verified": True,
            "distance_meters": _coarse(float(r.distance)),
        }
        for r, live in zip(rows, fresh, strict=True)
        if live is not None
    ]
