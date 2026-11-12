import pytest
from sqlalchemy import select, text

from app.core.redis import get_redis
from app.models.driver import DriverProfile
from tests.helpers import approved_driver, force_status, register_customer, register_driver

URL = "/api/v1/drivers/availability"


async def test_approved_driver_can_go_available_and_back_offline(client, db_session):
    h = await approved_driver(client, db_session)
    r = await client.patch(URL, headers=h, json={"status": "AVAILABLE"})
    assert r.status_code == 200 and r.json()["availability_status"] == "AVAILABLE"
    assert (await client.get("/api/v1/drivers/me", headers=h)).json()["availability_status"] == "AVAILABLE"
    r = await client.patch(URL, headers=h, json={"status": "OFFLINE"})
    assert r.json()["availability_status"] == "OFFLINE"


async def test_going_available_twice_is_fine(client, db_session):
    h = await approved_driver(client, db_session)
    await client.patch(URL, headers=h, json={"status": "AVAILABLE"})
    assert (await client.patch(URL, headers=h, json={"status": "AVAILABLE"})).status_code == 200


@pytest.mark.parametrize("verification", ["PENDING", "REJECTED"])
async def test_unapproved_driver_cannot_go_available(client, db_session, verification):
    h, _ = await register_driver(client)
    await force_status(db_session, verification_status=verification)
    r = await client.patch(URL, headers=h, json={"status": "AVAILABLE"})
    assert r.status_code == 403
    assert "approved" in r.json()["detail"].lower()


@pytest.mark.parametrize("state", ["RESERVED", "BOOKED", "ON_TRIP", "SUSPENDED"])
async def test_driver_cannot_change_availability_while_reserved_booked_on_trip_or_suspended(client, db_session, state):
    h = await approved_driver(client, db_session)
    await force_status(db_session, availability_status=state)
    for target in ("OFFLINE", "AVAILABLE"):
        assert (await client.patch(URL, headers=h, json={"status": target})).status_code == 409, (state, target)
    db_session.expire_all()
    assert (await db_session.execute(select(DriverProfile.availability_status))).scalar_one() == state


@pytest.mark.parametrize("bad", ["ON_TRIP", "BOOKED", "SUSPENDED", "online", ""])
async def test_drivers_cannot_set_system_states_or_junk(client, db_session, bad):
    h = await approved_driver(client, db_session)
    assert (await client.patch(URL, headers=h, json={"status": bad})).status_code == 422


async def test_going_offline_forgets_the_live_location(client, db_session):
    h = await approved_driver(client, db_session)
    await client.patch(URL, headers=h, json={"status": "AVAILABLE"})
    pid = (await db_session.execute(text("select id from driver_profiles"))).scalar_one()
    await get_redis().set(f"driver:location:{pid}", "{}", ex=30)
    await db_session.execute(text("insert into driver_locations (driver_id, location) values (:d, ST_SetSRID(ST_MakePoint(80.3, 26.4), 4326)::geography)"), {"d": pid})
    await db_session.commit()
    await client.patch(URL, headers=h, json={"status": "OFFLINE"})
    assert await get_redis().get(f"driver:location:{pid}") is None
    assert (await db_session.execute(text("select count(*) from driver_locations"))).scalar_one() == 0


async def test_customers_and_anonymous_cannot_change_availability(client):
    c = await register_customer(client)
    assert (await client.patch(URL, headers=c, json={"status": "AVAILABLE"})).status_code == 403
    assert (await client.patch(URL, json={"status": "AVAILABLE"})).status_code == 401
