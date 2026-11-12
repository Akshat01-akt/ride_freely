from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import (
    InvalidTokenError,
    create_token,
    decode_token,
    hash_password,
    hash_password_async,
    verify_password_async,
)
from app.models.customer import CustomerProfile
from app.models.driver import DriverProfile
from app.models.user import Role, User
from app.schemas.auth import CustomerRegister, DriverRegister, TokenPair

# Verified against when the phone is unknown, so login timing doesn't reveal which phones exist.
_DUMMY_HASH = hash_password("not-a-real-password")


class PhoneAlreadyRegistered(Exception):
    pass


class InvalidCredentials(Exception):
    pass


def issue_tokens(user: User) -> TokenPair:
    return TokenPair(
        access_token=create_token(user.id, user.role, "access"),
        refresh_token=create_token(user.id, user.role, "refresh"),
    )


async def _create_user(session: AsyncSession, data: CustomerRegister, role: Role) -> User:
    existing = await session.scalar(select(User.id).where(User.phone == data.phone))
    if existing is not None:
        raise PhoneAlreadyRegistered
    user = User(
        full_name=data.full_name,
        phone=data.phone,
        email=data.email,
        password_hash=await hash_password_async(data.password),
        role=role,
    )
    session.add(user)
    await session.flush()
    return user


async def register_customer(session: AsyncSession, data: CustomerRegister) -> User:
    try:
        user = await _create_user(session, data, Role.CUSTOMER)
        session.add(CustomerProfile(user_id=user.id))
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise PhoneAlreadyRegistered from None
    except PhoneAlreadyRegistered:
        await session.rollback()
        raise
    return user


async def register_driver(session: AsyncSession, data: DriverRegister) -> User:
    try:
        user = await _create_user(session, data, Role.DRIVER)
        session.add(
            DriverProfile(
                user_id=user.id,
                licence_number=data.licence_number,
                experience_years=data.experience_years,
                hourly_rate=data.hourly_rate,
            )
        )
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise PhoneAlreadyRegistered from None
    except PhoneAlreadyRegistered:
        await session.rollback()
        raise
    return user


async def authenticate(session: AsyncSession, phone: str, password: str, role: Role) -> User:
    user = await session.scalar(select(User).where(User.phone == phone))
    hashed = user.password_hash if user is not None else _DUMMY_HASH
    password_ok = await verify_password_async(password, hashed)
    if user is None or not password_ok or user.role != role or not user.is_active:
        raise InvalidCredentials
    return user


async def refresh(session: AsyncSession, refresh_token: str) -> TokenPair:
    try:
        payload = decode_token(refresh_token, "refresh")
    except InvalidTokenError:
        raise InvalidCredentials from None
    user = await session.get(User, payload.sub)
    if user is None or not user.is_active:
        raise InvalidCredentials
    return issue_tokens(user)
