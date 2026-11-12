import asyncio
from datetime import UTC, datetime, timedelta

import pytest

from .helpers import approved_driver, force_status, register_customer
from .test_bookings_api import DPHONE, URL, create, profile_id, set_booking, setup


async def completed(client, db_session, ch, dh, pid, hours_ago=0):
    """A finished trip: book now, accept, start, complete."""
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    b = await create(client, ch, pid, start_time=datetime.now(UTC).isoformat(), hours=1)
    for action in ("accept", "start", "complete"):
        r = await client.post(f"{URL}/{b['id']}/{action}", headers=dh)
        assert r.status_code == 200, r.text
    return b


async def rate(client, headers, booking_id, value):
    return await client.post(f"{URL}/{booking_id}/rating", json={"rating": value}, headers=headers)


async def test_customer_rates_a_completed_trip_and_driver_average_updates(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await completed(client, db_session, ch, dh, pid)
    r = await rate(client, ch, b["id"], 4)
    assert r.status_code == 200
    assert r.json()["rating"] == 4
    assert (await client.get("/api/v1/drivers/me", headers=dh)).json()["rating"] == "4.00"
    assert (await client.get(f"{URL}/{b['id']}", headers=dh)).json()["rating"] == 4


async def _days_ago(db_session, booking, days):
    """Move a finished trip into the past so the next trip does not overlap it."""
    past = datetime.now(UTC) - timedelta(days=days)
    await set_booking(db_session, booking["id"], start_time=past, end_time=past + timedelta(hours=1))


async def test_driver_rating_is_the_average_of_rated_trips_only(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    other = await register_customer(client, "+919876543299")
    first = await completed(client, db_session, ch, dh, pid)
    await _days_ago(db_session, first, 1)
    second = await completed(client, db_session, other, dh, pid)
    await _days_ago(db_session, second, 2)
    await completed(client, db_session, ch, dh, pid)  # a third trip that is never rated must not count as 0
    await rate(client, ch, first["id"], 5)
    await rate(client, other, second["id"], 2)
    assert (await client.get("/api/v1/drivers/me", headers=dh)).json()["rating"] == "3.50"


@pytest.mark.parametrize("value", [0, 6, -1, 4.5, "5", None])
async def test_bad_ratings_are_422(client, db_session, value):
    ch, dh, pid = await setup(client, db_session)
    b = await completed(client, db_session, ch, dh, pid)
    assert (await rate(client, ch, b["id"], value)).status_code == 422


async def test_missing_rating_field_is_422(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await completed(client, db_session, ch, dh, pid)
    assert (await client.post(f"{URL}/{b['id']}/rating", json={}, headers=ch)).status_code == 422


async def test_only_completed_trips_can_be_rated(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    assert (await rate(client, ch, b["id"], 5)).status_code == 409


async def test_a_trip_can_only_be_rated_once_even_with_simultaneous_requests(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await completed(client, db_session, ch, dh, pid)
    rs = await asyncio.gather(rate(client, ch, b["id"], 5), rate(client, ch, b["id"], 1))
    assert sorted(r.status_code for r in rs) == [200, 409]
    assert (await client.get("/api/v1/drivers/me", headers=dh)).json()["rating"] in ("5.00", "1.00")


async def test_nobody_else_can_rate(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await completed(client, db_session, ch, dh, pid)
    stranger = await register_customer(client, "+919876543299")
    assert (await rate(client, stranger, b["id"], 5)).status_code == 404
    assert (await rate(client, dh, b["id"], 5)).status_code == 403
    assert (await client.post(f"{URL}/{b['id']}/rating", json={"rating": 5})).status_code == 401


async def test_complete_records_when_the_trip_finished(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await completed(client, db_session, ch, dh, pid)
    from sqlalchemy import select

    from app.models.booking import Booking

    row = (await db_session.execute(select(Booking).where(Booking.id == b["id"]))).scalar_one()
    assert row.completed_at is not None
    assert abs((datetime.now(UTC) - row.completed_at).total_seconds()) < 30
