import uuid
from datetime import timedelta

import pytest

from app.core.security import (
    InvalidTokenError,
    create_token,
    decode_token,
    hash_password,
    verify_password,
)


def test_password_roundtrip():
    hashed = hash_password("s3cret-pass")
    assert verify_password("s3cret-pass", hashed)
    assert not verify_password("wrong", hashed)


def test_hash_is_argon2():
    assert hash_password("s3cret-pass").startswith("$argon2id$")


def test_access_token_roundtrip_carries_role_and_subject():
    uid = uuid.uuid4()
    payload = decode_token(create_token(uid, "driver", "access"), "access")
    assert payload.sub == uid
    assert payload.role == "driver"
    assert payload.type == "access"


def test_refresh_token_rejected_as_access():
    token = create_token(uuid.uuid4(), "customer", "refresh")
    with pytest.raises(InvalidTokenError):
        decode_token(token, "access")


def test_access_token_rejected_as_refresh():
    token = create_token(uuid.uuid4(), "customer", "access")
    with pytest.raises(InvalidTokenError):
        decode_token(token, "refresh")


def test_expired_token_rejected():
    token = create_token(uuid.uuid4(), "customer", "access", expires_delta=timedelta(seconds=-5))
    with pytest.raises(InvalidTokenError):
        decode_token(token, "access")


def test_tampered_token_rejected():
    token = create_token(uuid.uuid4(), "customer", "access")
    head, body, sig = token.split(".")
    with pytest.raises(InvalidTokenError):
        decode_token(f"{head}.{body}.{sig[:-2]}xx", "access")


def test_garbage_token_rejected():
    with pytest.raises(InvalidTokenError):
        decode_token("not-a-jwt", "access")
