import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal

import jwt
from fastapi.concurrency import run_in_threadpool
from pwdlib import PasswordHash
from pwdlib.hashers.argon2 import Argon2Hasher

from app.core.config import get_settings

_hasher = PasswordHash((Argon2Hasher(),))

TokenType = Literal["access", "refresh"]


class InvalidTokenError(Exception):
    pass


@dataclass(frozen=True)
class TokenPayload:
    sub: uuid.UUID
    role: str
    type: str


def hash_password(plain: str) -> str:
    return _hasher.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _hasher.verify(plain, hashed)


async def hash_password_async(plain: str) -> str:
    # Argon2 is deliberately slow; keep it off the event loop.
    return await run_in_threadpool(hash_password, plain)


async def verify_password_async(plain: str, hashed: str) -> bool:
    return await run_in_threadpool(verify_password, plain, hashed)


def create_token(
    user_id: uuid.UUID, role: str, token_type: TokenType, expires_delta: timedelta | None = None
) -> str:
    settings = get_settings()
    if expires_delta is None:
        expires_delta = (
            timedelta(minutes=settings.access_token_minutes)
            if token_type == "access"
            else timedelta(days=settings.refresh_token_days)
        )
    now = datetime.now(UTC)
    claims = {"sub": str(user_id), "role": role, "type": token_type, "iat": now, "exp": now + expires_delta}
    return jwt.encode(claims, settings.secret_key, algorithm="HS256")


def decode_token(token: str, expected_type: TokenType) -> TokenPayload:
    try:
        claims = jwt.decode(token, get_settings().secret_key, algorithms=["HS256"], options={"require": ["exp", "sub"]})
        payload = TokenPayload(sub=uuid.UUID(claims["sub"]), role=claims["role"], type=claims["type"])
    except (jwt.PyJWTError, KeyError, ValueError) as exc:
        raise InvalidTokenError(str(exc)) from exc
    if payload.type != expected_type:
        raise InvalidTokenError("wrong token type")
    return payload
