from datetime import UTC, datetime, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.models.booking import Booking, BookingStatus, BookingType
from app.models.customer import CustomerProfile

from .helpers import approved_driver, register_customer
from .test_bookings_api import DPHONE, profile_id

URL = "/api/v1/drivers/earnings"
IST = ZoneInfo("Asia/Kolkata")


def ist_midnight(now: datetime) -> datetime:
    return now.astimezone(IST).replace(hour=0, minute=0, second=0, microsecond=0)


async def add_trip(db_session, pid, price, completed_at, status=BookingStatus.COMPLETED):
    cp = (await db_session.execute(select(CustomerProfile))).scalars().first()
    start = completed_at - timedelta(hours=1)
    db_session.add(Booking(
        customer_id=cp.id, driver_id=pid, booking_type=BookingType.HOURLY, start_time=start, end_time=completed_at,
        hours=1, pickup_address="x", price_amount=Decimal(price), status=status, expires_at=start,
        completed_at=completed_at if status == BookingStatus.COMPLETED else None,
    ))
    await db_session.commit()


async def test_no_trips_is_zeros_not_an_error(client, db_session):
    dh = await approved_driver(client, db_session)
    r = await client.get(URL, headers=dh)
    assert r.status_code == 200
    zero = {"trips": 0, "amount": "0.00"}
    assert r.json() == {"today": zero, "week": zero, "month": zero, "total": zero}


async def test_sums_completed_trips_and_ignores_everything_else(client, db_session):
    dh = await approved_driver(client, db_session)
    await register_customer(client)
    pid = await profile_id(db_session)
    now = datetime.now(UTC)
    start = ist_midnight(now) + timedelta(seconds=1)
    await add_trip(db_session, pid, "180.00", start)
    await add_trip(db_session, pid, "90.50", start + timedelta(seconds=1))
    await add_trip(db_session, pid, "500.00", start, status=BookingStatus.CANCELLED)
    await add_trip(db_session, pid, "700.00", start, status=BookingStatus.ACCEPTED)
    body = (await client.get(URL, headers=dh)).json()
    assert body["today"] == {"trips": 2, "amount": "270.50"}
    assert body["total"] == {"trips": 2, "amount": "270.50"}


async def test_periods_follow_india_time(client, db_session):
    dh = await approved_driver(client, db_session)
    await register_customer(client)
    pid = await profile_id(db_session)
    today = ist_midnight(datetime.now(UTC))
    just_before = today - timedelta(seconds=1)  # 23:59:59 yesterday, India time
    await add_trip(db_session, pid, "100.00", today + timedelta(seconds=1))
    await add_trip(db_session, pid, "10.00", just_before)
    body = (await client.get(URL, headers=dh)).json()
    assert body["today"]["trips"] == 1
    monday = today.weekday() == 0
    first_of_month = today.day == 1
    assert body["week"]["trips"] == (1 if monday else 2)
    assert body["month"]["trips"] == (1 if first_of_month else 2)
    assert body["total"]["trips"] == 2


async def test_old_trips_count_only_in_total(client, db_session):
    dh = await approved_driver(client, db_session)
    await register_customer(client)
    pid = await profile_id(db_session)
    await add_trip(db_session, pid, "300.00", datetime.now(UTC) - timedelta(days=90))
    body = (await client.get(URL, headers=dh)).json()
    assert body["month"]["trips"] == 0 and body["total"] == {"trips": 1, "amount": "300.00"}


async def test_other_drivers_trips_are_not_mine(client, db_session):
    dh = await approved_driver(client, db_session)
    await approved_driver(client, db_session, "+919876500001")
    await register_customer(client)
    other = await profile_id(db_session, "+919876500001")
    await add_trip(db_session, other, "999.00", datetime.now(UTC))
    assert (await client.get(URL, headers=dh)).json()["total"]["trips"] == 0


async def test_only_drivers_can_read_earnings(client, db_session):
    ch = await register_customer(client)
    assert (await client.get(URL, headers=ch)).status_code == 403
    assert (await client.get(URL)).status_code == 401
