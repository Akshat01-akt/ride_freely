from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_role
from app.core.database import get_session
from app.models.customer import CustomerProfile
from app.models.user import Role, User
from app.schemas.auth import CustomerOut

router = APIRouter(prefix="/customers", tags=["customers"])


@router.get("/me", response_model=CustomerOut)
async def me(user: User = Depends(require_role(Role.CUSTOMER)), session: AsyncSession = Depends(get_session)):
    profile = await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id))
    return CustomerOut(
        id=user.id,
        full_name=user.full_name,
        phone=user.phone,
        email=user.email,
        default_address=profile.default_address if profile else None,
    )
