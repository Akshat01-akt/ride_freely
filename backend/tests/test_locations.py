import json

import pytest
from sqlalchemy import text

from app.core.redis import get_redis
from tests.helpers import approved_driver, force_status, register_customer, register_driver

URL = "/api/v1/locations/update"
GOOD = {"latitude": 26.4512, "longitude": 80.3350, "heading": 120, "speed": 5.5, "accuracy": 8.0}


async def _online(client, db_session, phone="+919876500000"):
    h = await approved_driver(client, db_session, phone)
    await client.patch("/api/v1/drivers/availability", headers=h, json={"status": "AVAILABLE"})
    return h


async def _pid(db_session):
    return (await db_session.execute(text("select id from driver_profiles limit 1"))).scalar_one()


async def test_available_driver_updates_location_in_redis_and_postgis(client, db_session):
    h = await _online(client, db_session)
    r = await client.post(URL, headers=h, json=GOOD)
    assert r.status_code == 204
    pid = await _pid(db_session)
    redis = get_redis()
    ttl = await redis.ttl(f"driver:location:{pid}")
    assert 0 < ttl <= 30
    payload = json.loads(await redis.get(f"driver:location:{pid}"))
    assert payload["latitude"] == 26.4512 and payload["longitude"] == 80.3350
    lng, lat = (await db_session.execute(text("select ST_X(location::geometry), ST_Y(location::geometry) from driver_locations"))).one()
    assert (round(lng, 4), round(lat, 4)) == (80.3350, 26.4512)  # longitude first, latitude second


async def test_later_updates_replace_the_earlier_position(client, db_session):
    h = await _online(client, db_session)
    await client.post(URL, headers=h, json=GOOD)
    await client.post(URL, headers=h, json={**GOOD, "latitude": 26.5, "longitude": 80.4})
    rows = (await db_session.execute(text("select ST_Y(location::geometry) from driver_locations"))).scalars().all()
    assert [round(x, 1) for x in rows] == [26.5]


async def test_only_latitude_and_longitude_are_required(client, db_session):
    h = await _online(client, db_session)
    assert (await client.post(URL, headers=h, json={"latitude": 1.5, "longitude": 2.5})).status_code == 204


@pytest.mark.parametrize("state", ["RESERVED", "BOOKED", "ON_TRIP"])
async def test_drivers_on_a_booking_keep_reporting_location(client, db_session, state):
    h = await _online(client, db_session)
    await force_status(db_session, availability_status=state)
    assert (await client.post(URL, headers=h, json=GOOD)).status_code == 204


@pytest.mark.parametrize("state", ["OFFLINE", "SUSPENDED"])
async def test_offline_or_suspended_drivers_cannot_report_location(client, db_session, state):
    h = await approved_driver(client, db_session)
    await force_status(db_session, availability_status=state)
    assert (await client.post(URL, headers=h, json=GOOD)).status_code == 409
    pid = await _pid(db_session)
    assert await get_redis().get(f"driver:location:{pid}") is None


async def test_unapproved_driver_cannot_report_location_even_if_marked_available(client, db_session):
    h, _ = await register_driver(client)
    await force_status(db_session, availability_status="AVAILABLE")
    assert (await client.post(URL, headers=h, json=GOOD)).status_code == 403


@pytest.mark.parametrize(
    "bad",
    [
        {"latitude": 90.1, "longitude": 0},
        {"latitude": -91, "longitude": 0},
        {"latitude": 0, "longitude": 180.5},
        {"latitude": 0, "longitude": -181},
        {"latitude": 0},
        {"longitude": 0},
        {"latitude": "north", "longitude": 0},
        {"latitude": 0, "longitude": 0, "heading": 361},
        {"latitude": 0, "longitude": 0, "heading": -1},
        {"latitude": 0, "longitude": 0, "speed": -3},
        {"latitude": 0, "longitude": 0, "accuracy": -1},
    ],
)
async def test_invalid_coordinates_and_extras_are_rejected(client, db_session, bad):
    h = await _online(client, db_session)
    assert (await client.post(URL, headers=h, json=bad)).status_code == 422


@pytest.mark.parametrize("raw", ['{"latitude": NaN, "longitude": 1}', '{"latitude": 1, "longitude": Infinity}'])
async def test_nan_and_infinity_are_rejected(client, db_session, raw):
    h = await _online(client, db_session)
    r = await client.post(URL, headers={**h, "content-type": "application/json"}, content=raw)
    assert r.status_code == 422


async def test_customers_and_anonymous_cannot_post_locations(client):
    c = await register_customer(client)
    assert (await client.post(URL, headers=c, json=GOOD)).status_code == 403
    assert (await client.post(URL, json=GOOD)).status_code == 401
