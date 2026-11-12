import pytest
from sqlalchemy.exc import IntegrityError

from app.models.driver import DriverProfile
from app.models.user import User


def _user(phone: str, role: str = "customer") -> User:
    return User(full_name="Test", phone=phone, password_hash="x", role=role)


async def test_user_phone_is_unique(db_session):
    db_session.add(_user("+919999900001"))
    await db_session.commit()
    db_session.add(_user("+919999900001"))
    with pytest.raises(IntegrityError):
        await db_session.commit()


async def test_driver_profile_defaults(db_session):
    user = _user("+919999900002", role="driver")
    db_session.add(user)
    await db_session.flush()
    db_session.add(
        DriverProfile(user_id=user.id, licence_number="DL123", experience_years=3, hourly_rate=150)
    )
    await db_session.commit()
    profile = (await db_session.execute(DriverProfile.__table__.select())).first()
    assert profile.verification_status == "PENDING"
    assert profile.availability_status == "OFFLINE"
    assert profile.rating == 0
