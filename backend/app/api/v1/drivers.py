from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_role
from app.core.database import get_session
from app.models.driver import DriverProfile
from app.models.user import Role, User
from app.schemas.auth import DriverOut

router = APIRouter(prefix="/drivers", tags=["drivers"])


@router.get("/me", response_model=DriverOut)
async def me(user: User = Depends(require_role(Role.DRIVER)), session: AsyncSession = Depends(get_session)):
    profile = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id))
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Driver profile not found")
    return DriverOut(
        id=user.id,
        full_name=user.full_name,
        phone=user.phone,
        email=user.email,
        licence_number=profile.licence_number,
        experience_years=profile.experience_years,
        hourly_rate=profile.hourly_rate,
        verification_status=profile.verification_status,
        availability_status=profile.availability_status,
        rating=profile.rating,
    )
