import asyncio
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select, update

from app.core.database import SessionLocal
from app.models.booking import Booking, BookingStatus
from app.models.driver import DriverProfile
from app.models.user import User

from .helpers import admin_headers, approved_driver, force_status, register_customer

URL = "/api/v1/bookings"
DPHONE = "+919876500000"
LATER = lambda h=0: (datetime.now(UTC) + timedelta(days=2, hours=h)).isoformat()  # noqa: E731


async def profile_id(db_session, phone=DPHONE):
    uid = await db_session.scalar(select(User.id).where(User.phone == phone))
    return str(await db_session.scalar(select(DriverProfile.id).where(DriverProfile.user_id == uid)))


def body(pid, **over):
    return {"driver_id": pid, "booking_type": "HOURLY", "start_time": LATER(), "hours": 2,
            "pickup_address": "12 MG Road", **over}


async def setup(client, db_session):
    ch = await register_customer(client)
    dh = await approved_driver(client, db_session)
    return ch, dh, await profile_id(db_session)


async def create(client, ch, pid, **over):
    r = await client.post(URL, json=body(pid, **over), headers=ch)
    assert r.status_code == 201, r.text
    return r.json()


async def set_booking(db_session, booking_id, **values):
    await db_session.execute(update(Booking).where(Booking.id == booking_id).values(**values))
    await db_session.commit()


# ---------- create / read ----------

async def test_create_returns_the_booking_with_a_string_price(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    assert b["status"] == "REQUESTED"
    assert b["price_amount"] == "360.00"
    assert b["hours"] == 2
    assert b["driver"]["name"] == "Ravi Kumar"
    assert b["pickup_address"] == "12 MG Road"


async def test_phones_are_hidden_until_the_driver_accepts(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    assert "phone" not in b["driver"] and "phone" not in b["customer"]
    seen_by_driver = (await client.get(f"{URL}/{b['id']}", headers=dh)).json()
    assert "phone" not in seen_by_driver["customer"]
    await client.post(f"{URL}/{b['id']}/accept", headers=dh)
    assert (await client.get(f"{URL}/{b['id']}", headers=ch)).json()["driver"]["phone"] == DPHONE
    assert (await client.get(f"{URL}/{b['id']}", headers=dh)).json()["customer"]["phone"] == "+919876543210"


async def test_a_driver_or_anonymous_cannot_create(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    assert (await client.post(URL, json=body(pid), headers=dh)).status_code == 403
    assert (await client.post(URL, json=body(pid))).status_code == 401


async def test_an_admin_cannot_use_booking_endpoints(client, db_session):
    ah = await admin_headers(client, db_session)
    assert (await client.get(URL, headers=ah)).status_code == 403


@pytest.mark.parametrize(
    "over",
    [
        {"hours": 0}, {"hours": 13}, {"hours": None},
        {"start_time": (datetime.now(UTC) - timedelta(hours=2)).isoformat()},
        {"start_time": (datetime.now(UTC) + timedelta(days=40)).isoformat()},
        {"start_time": "2030-01-01T09:00:00"},
        {"start_time": "not a time"},
        {"pickup_address": "   "}, {"pickup_address": "x" * 301}, {"notes": "n" * 501},
        {"booking_type": "WEEKLY"}, {"driver_id": "nope"},
    ],
)
async def test_bad_input_is_422(client, db_session, over):
    ch, dh, pid = await setup(client, db_session)
    r = await client.post(URL, json=body(pid, **over), headers=ch)
    assert r.status_code == 422, r.text


async def test_missing_start_time_means_now_and_needs_an_available_driver(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    r = await client.post(URL, json={k: v for k, v in body(pid).items() if k != "start_time"}, headers=ch)
    assert r.status_code == 409  # approved but OFFLINE
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    r = await client.post(URL, json={k: v for k, v in body(pid).items() if k != "start_time"}, headers=ch)
    assert r.status_code == 201


async def test_unapproved_driver_is_409_and_unknown_driver_is_409(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await force_status(db_session, DPHONE, verification_status="REJECTED")
    assert (await client.post(URL, json=body(pid), headers=ch)).status_code == 409
    assert (await client.post(URL, json=body("00000000-0000-0000-0000-000000000000"), headers=ch)).status_code == 409


async def test_overlap_is_409_and_fourth_active_booking_is_409(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await create(client, ch, pid)
    other = await register_customer(client, "+919876543299")
    assert (await client.post(URL, json=body(pid, start_time=LATER(1)), headers=other)).status_code == 409
    for i in (3, 6):
        await create(client, ch, pid, start_time=LATER(i), hours=1)
    assert (await client.post(URL, json=body(pid, start_time=LATER(10), hours=1), headers=ch)).status_code == 409


async def test_lists_only_my_bookings_newest_first_for_each_role(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    other = await register_customer(client, "+919876543299")
    first = await create(client, ch, pid, start_time=LATER(0), hours=1)
    second = await create(client, other, pid, start_time=LATER(5), hours=1)
    mine = (await client.get(URL, headers=ch)).json()
    assert [b["id"] for b in mine] == [first["id"]]
    theirs = (await client.get(URL, headers=dh)).json()
    assert [b["id"] for b in theirs] == [second["id"], first["id"]]


async def test_other_peoples_bookings_are_404_for_every_action(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    stranger = await register_customer(client, "+919876543299")
    dh2 = await approved_driver(client, db_session, phone="+919876500001")
    for headers in (stranger, dh2):
        assert (await client.get(f"{URL}/{b['id']}", headers=headers)).status_code == 404
    assert (await client.post(f"{URL}/{b['id']}/cancel", headers=stranger)).status_code == 404
    for action in ("accept", "reject", "start", "complete"):
        assert (await client.post(f"{URL}/{b['id']}/{action}", headers=dh2)).status_code == 404
    assert (await client.get(f"{URL}/not-a-uuid", headers=ch)).status_code == 422


# ---------- transitions ----------

async def test_full_trip(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    b = await create(client, ch, pid, start_time=datetime.now(UTC).isoformat(), hours=1)
    assert (await client.post(f"{URL}/{b['id']}/accept", headers=dh)).json()["status"] == "ACCEPTED"
    assert (await client.post(f"{URL}/{b['id']}/start", headers=dh)).json()["status"] == "IN_PROGRESS"
    me = (await client.get("/api/v1/drivers/me", headers=dh)).json()
    assert me["availability_status"] == "ON_TRIP"
    assert (await client.post(f"{URL}/{b['id']}/complete", headers=dh)).json()["status"] == "COMPLETED"
    me = (await client.get("/api/v1/drivers/me", headers=dh)).json()
    assert me["availability_status"] == "OFFLINE"


async def test_reject_frees_the_slot(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    assert (await client.post(f"{URL}/{b['id']}/reject", headers=dh)).json()["status"] == "REJECTED"
    other = await register_customer(client, "+919876543299")
    assert (await client.post(URL, json=body(pid), headers=other)).status_code == 201


async def test_customer_cancels_a_requested_or_accepted_booking(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    assert (await client.post(f"{URL}/{b['id']}/cancel", headers=ch)).json()["status"] == "CANCELLED"
    b2 = await create(client, ch, pid)
    await client.post(f"{URL}/{b2['id']}/accept", headers=dh)
    assert (await client.post(f"{URL}/{b2['id']}/cancel", headers=ch)).json()["status"] == "CANCELLED"


@pytest.mark.parametrize(
    ("setup_status", "action", "who"),
    [
        ("ACCEPTED", "accept", "driver"), ("ACCEPTED", "reject", "driver"),
        ("REJECTED", "accept", "driver"), ("CANCELLED", "accept", "driver"),
        ("REQUESTED", "start", "driver"), ("REQUESTED", "complete", "driver"),
        ("ACCEPTED", "complete", "driver"),
        ("COMPLETED", "cancel", "customer"), ("IN_PROGRESS", "cancel", "customer"),
        ("REJECTED", "cancel", "customer"), ("CANCELLED", "cancel", "customer"),
    ],
)
async def test_illegal_transitions_are_409(client, db_session, setup_status, action, who):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    await set_booking(db_session, b["id"], status=setup_status)
    r = await client.post(f"{URL}/{b['id']}/{action}", headers=dh if who == "driver" else ch)
    assert r.status_code == 409, r.text


async def test_customer_cannot_use_driver_actions_and_driver_cannot_cancel(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    for action in ("accept", "reject", "start", "complete"):
        assert (await client.post(f"{URL}/{b['id']}/{action}", headers=ch)).status_code == 403
    assert (await client.post(f"{URL}/{b['id']}/cancel", headers=dh)).status_code == 403


async def test_an_expired_request_cannot_be_accepted_and_shows_as_expired(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    await set_booking(db_session, b["id"], expires_at=datetime.now(UTC) - timedelta(seconds=1))
    assert (await client.post(f"{URL}/{b['id']}/accept", headers=dh)).status_code == 409
    assert (await client.get(f"{URL}/{b['id']}", headers=ch)).json()["status"] == "EXPIRED"


async def test_start_is_refused_more_than_15_minutes_before_the_slot(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)  # two days away
    await client.post(f"{URL}/{b['id']}/accept", headers=dh)
    assert (await client.post(f"{URL}/{b['id']}/start", headers=dh)).status_code == 409


async def test_a_suspended_driver_cannot_start(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    b = await create(client, ch, pid, start_time=datetime.now(UTC).isoformat(), hours=1)
    await client.post(f"{URL}/{b['id']}/accept", headers=dh)
    await force_status(db_session, DPHONE, availability_status="SUSPENDED")
    assert (await client.post(f"{URL}/{b['id']}/start", headers=dh)).status_code == 409


async def test_double_accept_exactly_one_wins(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    rs = await asyncio.gather(*[client.post(f"{URL}/{b['id']}/accept", headers=dh) for _ in range(2)])
    assert sorted(r.status_code for r in rs) == [200, 409]


async def test_cancel_and_accept_race_ends_in_a_consistent_state(client, db_session):
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    a, c = await asyncio.gather(
        client.post(f"{URL}/{b['id']}/accept", headers=dh), client.post(f"{URL}/{b['id']}/cancel", headers=ch)
    )
    final = (await client.get(f"{URL}/{b['id']}", headers=ch)).json()["status"]
    assert c.status_code == 200 and final == "CANCELLED"  # cancel is legal from REQUESTED and ACCEPTED
    assert a.status_code in (200, 409)
