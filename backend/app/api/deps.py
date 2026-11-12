from collections.abc import Callable

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import InvalidTokenError, decode_token
from app.models.driver import DriverProfile
from app.models.user import Role, User

_bearer = HTTPBearer(auto_error=False)

_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Invalid or expired token",
    headers={"WWW-Authenticate": "Bearer"},
)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    if credentials is None:
        raise _UNAUTHORIZED
    try:
        payload = decode_token(credentials.credentials, "access")
    except InvalidTokenError:
        raise _UNAUTHORIZED from None
    user = await session.get(User, payload.sub)
    if user is None or not user.is_active:
        raise _UNAUTHORIZED
    return user


def require_role(*roles: str) -> Callable[..., User]:
    async def dependency(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed for this account type")
        return user

    return dependency


async def get_driver_profile(
    user: User = Depends(require_role(Role.DRIVER)), session: AsyncSession = Depends(get_session)
) -> DriverProfile:
    profile = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id))
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Driver profile not found")
    return profile
