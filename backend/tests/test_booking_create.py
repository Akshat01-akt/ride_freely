import asyncio
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import select

from app.core.database import SessionLocal
from app.models.booking import Booking, BookingStatus, BookingType
from app.models.customer import CustomerProfile
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.models.user import User
from app.services import booking_service as bs

NOW = datetime.now(UTC)
LATER = NOW + timedelta(days=2)


async def make_customer(db_session, phone="+919999900020") -> CustomerProfile:
    u = User(full_name="Asha", phone=phone, password_hash="x", role="customer")
    db_session.add(u)
    await db_session.flush()
    c = CustomerProfile(user_id=u.id)
    db_session.add(c)
    await db_session.commit()
    return c


async def make_driver(
    db_session, phone="+919999900021", rate="180.00", verification=VerificationStatus.APPROVED,
    availability=AvailabilityStatus.AVAILABLE, active=True,
) -> DriverProfile:
    u = User(full_name="Ravi", phone=phone, password_hash="x", role="driver", is_active=active)
    db_session.add(u)
    await db_session.flush()
    d = DriverProfile(
        user_id=u.id, licence_number="DL1", experience_years=3, hourly_rate=Decimal(rate),
        verification_status=verification, availability_status=availability,
    )
    db_session.add(d)
    await db_session.commit()
    return d


async def book(db_session, c, d, start=LATER, kind=BookingType.HOURLY, hours=2, **kw):
    return await bs.create_booking(
        db_session, customer_id=c.id, driver_id=d.id, booking_type=kind, start_time=start,
        hours=hours, pickup_address=kw.pop("address", "12 MG Road"), notes=kw.pop("notes", None), **kw,
    )


async def test_hourly_price_and_window(db_session):
    c, d = await make_customer(db_session), await make_driver(db_session)
    b = await book(db_session, c, d, hours=3)
    assert b.status == BookingStatus.REQUESTED
    assert b.price_amount == Decimal("540.00")
    assert b.end_time - b.start_time == timedelta(hours=3)
    assert b.hours == 3
    assert timedelta(minutes=9) < b.expires_at - datetime.now(UTC) <= timedelta(minutes=10)


async def test_full_day_is_eight_billed_hours_whatever_hours_is_sent(db_session):
    c, d = await make_customer(db_session), await make_driver(db_session)
    b = await book(db_session, c, d, kind=BookingType.FULL_DAY, hours=None)
    assert b.hours == 8
    assert b.price_amount == Decimal("1440.00")
    assert b.end_time - b.start_time == timedelta(hours=8)


@pytest.mark.parametrize("hours", [0, 13, -1, None])
async def test_hourly_hours_must_be_1_to_12(db_session, hours):
    c, d = await make_customer(db_session), await make_driver(db_session)
    with pytest.raises(bs.InvalidWindow):
        await book(db_session, c, d, hours=hours)


@pytest.mark.parametrize(
    "start", [NOW - timedelta(hours=1), NOW + timedelta(days=31), datetime(2031, 1, 1, 9, 0)]
)
async def test_start_must_be_recent_future_within_30_days_and_timezone_aware(db_session, start):
    c, d = await make_customer(db_session), await make_driver(db_session)
    with pytest.raises(bs.InvalidWindow):
        await book(db_session, c, d, start=start)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"verification": VerificationStatus.PENDING},
        {"verification": VerificationStatus.REJECTED},
        {"availability": AvailabilityStatus.SUSPENDED},
        {"active": False},
    ],
)
async def test_unapproved_suspended_or_inactive_drivers_cannot_be_booked(db_session, kwargs):
    c, d = await make_customer(db_session), await make_driver(db_session, **kwargs)
    with pytest.raises(bs.DriverUnavailable):
        await book(db_session, c, d)


async def test_book_now_needs_an_available_driver_but_a_later_slot_does_not(db_session):
    c = await make_customer(db_session)
    d = await make_driver(db_session, availability=AvailabilityStatus.OFFLINE)
    with pytest.raises(bs.DriverUnavailable):
        await book(db_session, c, d, start=datetime.now(UTC))
    assert (await book(db_session, c, d, start=LATER)).status == BookingStatus.REQUESTED


async def test_unknown_driver_is_unavailable(db_session):
    c = await make_customer(db_session)
    with pytest.raises(bs.DriverUnavailable):
        await bs.create_booking(
            db_session, customer_id=c.id, driver_id=uuid.uuid4(), booking_type=BookingType.HOURLY,
            start_time=LATER, hours=1, pickup_address="x", notes=None,
        )


async def test_overlap_is_a_conflict_and_back_to_back_is_fine(db_session):
    c1 = await make_customer(db_session)
    c2 = await make_customer(db_session, "+919999900022")
    d = await make_driver(db_session)
    await book(db_session, c1, d, start=LATER, hours=2)
    with pytest.raises(bs.SlotTaken):
        await book(db_session, c2, d, start=LATER + timedelta(hours=1), hours=2)
    await db_session.refresh(c2)  # the refused request rolled the session back, which expires loaded objects
    await db_session.refresh(d)
    ok = await book(db_session, c2, d, start=LATER + timedelta(hours=2), hours=1)
    assert ok.status == BookingStatus.REQUESTED


async def test_a_customer_has_at_most_three_active_bookings(db_session):
    c = await make_customer(db_session)
    d = await make_driver(db_session)
    for i in range(3):
        await book(db_session, c, d, start=LATER + timedelta(hours=3 * i), hours=1)
    with pytest.raises(bs.TooManyBookings):
        await book(db_session, c, d, start=LATER + timedelta(hours=30), hours=1)


async def test_unanswered_request_expires_and_frees_the_slot(db_session):
    c1 = await make_customer(db_session)
    c2 = await make_customer(db_session, "+919999900022")
    d = await make_driver(db_session)
    first = await book(db_session, c1, d)
    first.expires_at = datetime.now(UTC) - timedelta(seconds=1)
    await db_session.commit()
    second = await book(db_session, c2, d)
    assert second.status == BookingStatus.REQUESTED
    await db_session.refresh(first)
    assert first.status == BookingStatus.EXPIRED


async def test_concurrent_requests_for_one_slot_exactly_one_wins(db_session):
    c1 = await make_customer(db_session)
    c2 = await make_customer(db_session, "+919999900022")
    d = await make_driver(db_session)

    async def attempt(c):
        async with SessionLocal() as s:
            try:
                await book(s, c, d)
                return "ok"
            except bs.SlotTaken:
                return "taken"

    results = await asyncio.gather(attempt(c1), attempt(c2))
    assert sorted(results) == ["ok", "taken"]
    rows = (await db_session.execute(select(Booking))).scalars().all()
    assert len(rows) == 1
