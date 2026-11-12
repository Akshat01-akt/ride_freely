from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from app.models.booking import ACTIVE_STATES, Booking, BookingStatus, BookingType
from app.models.customer import CustomerProfile
from app.models.driver import DriverProfile
from app.models.user import User

T0 = datetime(2030, 1, 1, 9, 0, tzinfo=UTC)


async def _people(db_session):
    cu = User(full_name="C", phone="+919999900010", password_hash="x", role="customer")
    du = User(full_name="D", phone="+919999900011", password_hash="x", role="driver")
    db_session.add_all([cu, du])
    await db_session.flush()
    c = CustomerProfile(user_id=cu.id)
    d = DriverProfile(user_id=du.id, licence_number="DL1", experience_years=1, hourly_rate=100)
    db_session.add_all([c, d])
    await db_session.commit()
    return c, d


def _booking(c, d, start, hours=2, status=BookingStatus.REQUESTED):
    return Booking(
        customer_id=c.id, driver_id=d.id, booking_type=BookingType.HOURLY, start_time=start,
        end_time=start + timedelta(hours=hours), hours=hours, pickup_address="Somewhere",
        price_amount=Decimal("200.00"), status=status, expires_at=start,
    )


async def test_active_states_are_the_ones_that_hold_a_slot():
    assert set(ACTIVE_STATES) == {BookingStatus.REQUESTED, BookingStatus.ACCEPTED, BookingStatus.IN_PROGRESS}


async def test_overlapping_active_bookings_for_one_driver_are_refused(db_session):
    c, d = await _people(db_session)
    db_session.add(_booking(c, d, T0))
    await db_session.commit()
    db_session.add(_booking(c, d, T0 + timedelta(hours=1)))
    with pytest.raises(IntegrityError):
        await db_session.commit()


async def test_back_to_back_slots_are_allowed(db_session):
    c, d = await _people(db_session)
    db_session.add(_booking(c, d, T0))
    db_session.add(_booking(c, d, T0 + timedelta(hours=2)))
    await db_session.commit()


@pytest.mark.parametrize(
    "status", [BookingStatus.CANCELLED, BookingStatus.REJECTED, BookingStatus.EXPIRED, BookingStatus.COMPLETED]
)
async def test_finished_bookings_do_not_block_the_slot(db_session, status):
    c, d = await _people(db_session)
    db_session.add(_booking(c, d, T0, status=status))
    db_session.add(_booking(c, d, T0))
    await db_session.commit()
