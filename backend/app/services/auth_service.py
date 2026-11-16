from sqlalchemy import or_, select
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
from app.schemas.auth import CustomerRegister, DriverRegister, TokenPair, normalize_phone

# Verified against when the account is unknown, so login timing doesn't reveal which accounts exist.
_DUMMY_HASH = hash_password("not-a-real-password")


class IdentifierTaken(Exception):
    """The email address or mobile number belongs to another account."""


class InvalidCredentials(Exception):
    pass


def issue_tokens(user: User) -> TokenPair:
    return TokenPair(
        access_token=create_token(user.id, user.role, "access"),
        refresh_token=create_token(user.id, user.role, "refresh"),
    )


async def _create_user(session: AsyncSession, data: CustomerRegister, role: Role) -> User:
    clash = []
    if data.phone is not None:
        clash.append(User.phone == data.phone)
    if data.email is not None:
        clash.append(User.email_normalized == data.email.lower())
    if await session.scalar(select(User.id).where(or_(*clash))) is not None:
        raise IdentifierTaken
    user = User(
        full_name=data.full_name,
        phone=data.phone,
        email=data.email,
        email_normalized=data.email.lower() if data.email else None,
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
        raise IdentifierTaken from None
    except IdentifierTaken:
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
        raise IdentifierTaken from None
    except IdentifierTaken:
        await session.rollback()
        raise
    return user


async def create_admin(session: AsyncSession, full_name: str, phone: str, password: str) -> User:
    data = CustomerRegister(full_name=full_name, phone=phone, password=password)
    try:
        user = await _create_user(session, data, Role.ADMIN)
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise IdentifierTaken from None
    except IdentifierTaken:
        await session.rollback()
        raise
    return user


def _lookup_clause(identifier: str):
    """An identifier with "@" is an email address, anything else a mobile number. None when it is neither."""
    identifier = identifier.strip()
    if "@" in identifier:
        return User.email_normalized == identifier.lower()
    try:
        return User.phone == normalize_phone(identifier)
    except ValueError:
        return None


async def authenticate(session: AsyncSession, identifier: str, password: str, role: Role) -> User:
    clause = _lookup_clause(identifier)
    user = await session.scalar(select(User).where(clause)) if clause is not None else None
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
