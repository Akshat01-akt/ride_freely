import pytest
from sqlalchemy import text, update

from app.core.redis import get_redis
from app.models.user import User
from tests.helpers import approved_driver, force_status, register_customer

URL = "/api/v1/drivers/nearby"
HERE = {"latitude": 26.4499, "longitude": 80.3319}
# ~0.009 degrees of latitude is about 1 km
NEAR = (26.4589, 80.3319)   # ~1 km north
FAR = (26.4859, 80.3319)    # ~4 km north
TOO_FAR = (26.5219, 80.3319)  # ~8 km north


async def _go_online(client, db_session, phone, at, rate="150.00", name=None):
    h = await approved_driver(client, db_session, phone) if name is None else None
    await client.patch("/api/v1/drivers/availability", headers=h, json={"status": "AVAILABLE"})
    r = await client.post("/api/v1/locations/update", headers=h, json={"latitude": at[0], "longitude": at[1]})
    assert r.status_code == 204
    return h


async def _search(client, customer, **params):
    return await client.get(URL, headers=customer, params={**HERE, **params})


async def test_nearby_drivers_are_sorted_by_distance(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500002", FAR)
    await _go_online(client, db_session, "+919876500001", NEAR)
    r = await _search(client, c)
    assert r.status_code == 200
    drivers = r.json()["drivers"]
    assert len(drivers) == 2
    d = [x["distance_meters"] for x in drivers]
    assert d == sorted(d) and 900 < d[0] < 1100 and 3800 < d[1] < 4200


async def test_response_exposes_no_exact_location_or_private_details(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", NEAR)
    [d] = (await _search(client, c)).json()["drivers"]
    assert set(d) == {"id", "name", "hourly_rate", "rating", "experience_years", "verified", "distance_meters"}
    assert d["verified"] is True and d["name"] == "Ravi Kumar"
    assert d["hourly_rate"] == "150.00"  # money is a string, like the rest of the API


async def test_default_radius_is_5km_and_it_can_be_widened(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", TOO_FAR)
    assert (await _search(client, c)).json()["drivers"] == []
    assert len((await _search(client, c, radius=10000)).json()["drivers"]) == 1


async def test_a_driver_exactly_at_the_radius_is_included(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", NEAR)
    exact = (await _search(client, c)).json()["drivers"][0]["distance_meters"]
    assert len((await _search(client, c, radius=exact)).json()["drivers"]) == 1
    assert (await _search(client, c, radius=exact - 1)).json()["drivers"] == []


async def test_a_driver_whose_location_expired_is_not_listed(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", NEAR)
    pid = (await db_session.execute(text("select id from driver_profiles"))).scalar_one()
    await get_redis().delete(f"driver:location:{pid}")
    assert (await _search(client, c)).json()["drivers"] == []


@pytest.mark.parametrize("state", ["OFFLINE", "RESERVED", "BOOKED", "ON_TRIP", "SUSPENDED"])
async def test_only_available_drivers_are_listed(client, db_session, state):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", NEAR)
    await force_status(db_session, "+919876500001", availability_status=state)
    assert (await _search(client, c)).json()["drivers"] == []


@pytest.mark.parametrize("verification", ["PENDING", "REJECTED"])
async def test_unverified_drivers_are_never_listed(client, db_session, verification):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", NEAR)
    await force_status(db_session, "+919876500001", verification_status=verification)
    assert (await _search(client, c)).json()["drivers"] == []


async def test_deactivated_drivers_are_not_listed(client, db_session):
    c = await register_customer(client)
    await _go_online(client, db_session, "+919876500001", NEAR)
    await db_session.execute(update(User).where(User.phone == "+919876500001").values(is_active=False))
    await db_session.commit()
    assert (await _search(client, c)).json()["drivers"] == []


@pytest.mark.parametrize("bad", [{"radius": 0}, {"radius": -1}, {"radius": 20001}, {"radius": "far"}, {"latitude": 95}, {"longitude": -200}])
async def test_invalid_search_parameters_are_rejected(client, bad):
    c = await register_customer(client)
    assert (await _search(client, c, **bad)).status_code == 422


async def test_search_needs_a_location(client):
    c = await register_customer(client)
    assert (await client.get(URL, headers=c)).status_code == 422


async def test_only_customers_can_search(client, db_session):
    d = await approved_driver(client, db_session)
    assert (await client.get(URL, headers=d, params=HERE)).status_code == 403
    assert (await client.get(URL, params=HERE)).status_code == 401
