import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.models.booking import Booking

from .helpers import admin_headers, approved_driver, force_status, register_customer
from .test_bookings_api import DPHONE, LATER, URL, create, profile_id, set_booking, setup
from .test_nearby import NEAR, _go_online, _search


async def _accepted_future(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    assert (await client.post(f"{URL}/{b['id']}/accept", headers=dh)).status_code == 200
    return ch, dh, pid, b


# ---- 1. driver standing is checked when accepting and starting ----

async def test_a_suspended_or_rejected_driver_cannot_accept(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    await force_status(db_session, DPHONE, availability_status="SUSPENDED")
    assert (await client.post(f"{URL}/{b['id']}/accept", headers=dh)).status_code == 409
    await force_status(db_session, DPHONE, availability_status="OFFLINE", verification_status="REJECTED")
    assert (await client.post(f"{URL}/{b['id']}/accept", headers=dh)).status_code == 409


async def test_a_rejected_driver_cannot_start(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    b = await create(client, ch, pid, start_time=datetime.now(UTC).isoformat(), hours=1)
    await client.post(f"{URL}/{b['id']}/accept", headers=dh)
    await force_status(db_session, DPHONE, verification_status="REJECTED")
    assert (await client.post(f"{URL}/{b['id']}/start", headers=dh)).status_code == 409


async def test_admin_cannot_suspend_or_reject_a_driver_with_an_accepted_booking(client, db_session):
    ch, dh, pid, b = await _accepted_future(client, db_session)
    ah = await admin_headers(client, db_session)
    r = await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", json={"suspended": True}, headers=ah)
    assert r.status_code == 409
    r = await client.patch(f"/api/v1/admin/drivers/{pid}/verification", json={"status": "REJECTED"}, headers=ah)
    assert r.status_code == 409
    # once the booking is over the driver can be suspended
    await client.post(f"{URL}/{b['id']}/cancel", headers=ch)
    r = await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", json={"suspended": True}, headers=ah)
    assert r.status_code == 200


async def test_an_unanswered_request_does_not_stop_suspension(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await create(client, ch, pid)
    ah = await admin_headers(client, db_session)
    r = await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", json={"suspended": True}, headers=ah)
    assert r.status_code == 200


# ---- 2. back-to-back trips ----

async def test_a_driver_cannot_start_a_second_trip_while_one_is_in_progress(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    a = await create(client, ch, pid, start_time=datetime.now(UTC).isoformat(), hours=1)
    await client.post(f"{URL}/{a['id']}/accept", headers=dh)
    await client.post(f"{URL}/{a['id']}/start", headers=dh)
    end_a = datetime.now(UTC) + timedelta(hours=1)
    b = await create(client, ch, pid, start_time=end_a.isoformat(), hours=1)
    await client.post(f"{URL}/{b['id']}/accept", headers=dh)
    now = datetime.now(UTC)
    await set_booking(db_session, a["id"], start_time=now - timedelta(minutes=50), end_time=now + timedelta(minutes=10))
    await set_booking(db_session, b["id"], start_time=now + timedelta(minutes=10), end_time=now + timedelta(minutes=70))
    assert (await client.post(f"{URL}/{b['id']}/start", headers=dh)).status_code == 409


# ---- 3. start only inside the window ----

async def test_a_booking_whose_window_has_passed_cannot_be_started(client, db_session):
    ch, dh, pid, b = await _accepted_future(client, db_session)
    long_ago = datetime.now(UTC) - timedelta(days=5)
    await set_booking(db_session, b["id"], start_time=long_ago, end_time=long_ago + timedelta(hours=1))
    assert (await client.post(f"{URL}/{b['id']}/start", headers=dh)).status_code == 409


# ---- 4. nearby ignores requests that already timed out ----

async def test_a_timed_out_request_does_not_hide_the_driver_from_nearby(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500000", NEAR)
    pid = await profile_id(db_session)
    r = await client.post(
        URL,
        json={"driver_id": pid, "booking_type": "FULL_DAY", "pickup_address": "x"},
        headers=c,
    )
    assert r.status_code == 201
    assert (await _search(client, c)).json()["drivers"] == []
    await set_booking(db_session, r.json()["id"], expires_at=datetime.now(UTC) - timedelta(seconds=1))
    assert len((await _search(client, c)).json()["drivers"]) == 1


# ---- 6. the limit of 3 holds under concurrency ----

async def test_the_three_booking_limit_holds_for_simultaneous_requests(client, db_session):
    ch = await register_customer(client)
    for i, phone in enumerate(["+919876500000", "+919876500001", "+919876500002", "+919876500003"]):
        await approved_driver(client, db_session, phone)
    pids = [await profile_id(db_session, p) for p in ["+919876500000", "+919876500001", "+919876500002", "+919876500003"]]
    for i in (0, 1):
        await create(client, ch, pids[i])
    rs = await asyncio.gather(*[
        client.post(URL, json={"driver_id": pids[i], "booking_type": "HOURLY", "start_time": LATER(), "hours": 1, "pickup_address": "x"}, headers=ch)
        for i in (2, 3)
    ])
    assert sorted(r.status_code for r in rs) == [201, 409]
    from app.models.booking import ACTIVE_STATES
    rows = (await db_session.execute(select(Booking).where(Booking.status.in_(ACTIVE_STATES)))).scalars().all()
    assert len(rows) == 3
