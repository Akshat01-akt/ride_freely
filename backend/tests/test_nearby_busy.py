from datetime import UTC, datetime, timedelta

from .test_bookings_api import URL as BOOKINGS, body, profile_id
from .test_nearby import NEAR, _go_online, _search
from .helpers import register_customer


async def _book(client, db_session, customer, pid, start):
    r = await client.post(BOOKINGS, json=body(pid, start_time=start.isoformat(), hours=2), headers=customer)
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def test_a_driver_with_a_booking_covering_now_is_hidden(client, db_session):
    c = await register_customer(client)
    dh = await _go_online(client, db_session, "+919876500000", NEAR)
    pid = await profile_id(db_session)
    b = await _book(client, db_session, c, pid, datetime.now(UTC))
    # A REQUESTED booking already holds the slot.
    assert (await _search(client, c)).json()["drivers"] == []
    await client.post(f"{BOOKINGS}/{b}/reject", headers=dh)
    assert len((await _search(client, c)).json()["drivers"]) == 1


async def test_a_driver_with_only_a_future_booking_is_still_listed(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500000", NEAR)
    pid = await profile_id(db_session)
    await _book(client, db_session, c, pid, datetime.now(UTC) + timedelta(days=2))
    assert len((await _search(client, c)).json()["drivers"]) == 1
