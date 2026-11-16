from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_role
from app.core.database import get_session
from app.models.customer import CustomerProfile
from app.models.user import Role, User
from app.schemas.auth import ApplicationIn, CustomerOut
from app.services import customer_profile_service
from app.services.application_service import ApplicationInvalid

router = APIRouter(prefix="/customers", tags=["customers"])


async def _profile(session: AsyncSession, user: User) -> CustomerProfile | None:
    return await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id))


@router.get("/me", response_model=CustomerOut)
async def me(user: User = Depends(require_role(Role.CUSTOMER)), session: AsyncSession = Depends(get_session)):
    profile = await _profile(session, user)
    return CustomerOut(
        id=user.id,
        full_name=user.full_name,
        phone=user.phone,
        email=user.email,
        default_address=profile.default_address if profile else None,
        profile=await customer_profile_service.view(session, profile) if profile else None,
    )


@router.put("/profile", response_model=CustomerOut)
async def save_profile(
    body: ApplicationIn, user: User = Depends(require_role(Role.CUSTOMER)), session: AsyncSession = Depends(get_session)
):
    profile = await _profile(session, user)
    if profile is None:
        raise HTTPException(404, "Customer profile not found")
    try:
        await customer_profile_service.save(session, profile, body.answers)
    except ApplicationInvalid as exc:
        raise HTTPException(
            422, [{"loc": ["answers", key], "msg": msg, "type": "value_error"} for key, msg in exc.errors.items()]
        ) from None
    return await me(user, session)
