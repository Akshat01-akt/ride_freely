from fastapi import APIRouter, Depends, HTTPException, Response, status
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_driver_profile
from app.core.database import get_session
from app.core.redis import get_redis
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.schemas.auth import LocationUpdate
from app.services.location_service import record_location

router = APIRouter(prefix="/locations", tags=["locations"])

_REPORTING = {AvailabilityStatus.AVAILABLE, AvailabilityStatus.RESERVED, AvailabilityStatus.BOOKED, AvailabilityStatus.ON_TRIP}


@router.post("/update", status_code=status.HTTP_204_NO_CONTENT)
async def update_location(
    body: LocationUpdate,
    profile: DriverProfile = Depends(get_driver_profile),
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    if profile.verification_status != VerificationStatus.APPROVED:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Your documents must be approved first")
    if profile.availability_status not in _REPORTING:
        raise HTTPException(status.HTTP_409_CONFLICT, "Go online before sharing your location")
    await record_location(session, redis, profile.id, body.latitude, body.longitude, body.heading, body.speed, body.accuracy)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
