from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text, update

from app.core.redis import get_redis
from app.models.driver import DriverProfile
from app.services import review_service
from tests.helpers import (admin_headers, apply_driver, approved_driver, bearer, force_status, profile_id, register_customer,
                           register_driver, signup_driver)

A = "/api/v1/admin"
NEAR = {"latitude": 26.4589, "longitude": 80.3319}


async def _online(client, db_session, phone, at=NEAR, name=None):
    h = await approved_driver(client, db_session, phone)
    await client.patch("/api/v1/drivers/availability", headers=h, json={"status": "AVAILABLE"})
    assert (await client.post("/api/v1/locations/update", headers=h, json=at)).status_code == 204
    return h


async def _booking(client, db_session, driver_phone="+919876500000"):
    ch = await register_customer(client)
    await approved_driver(client, db_session, driver_phone)
    pid = str(await profile_id(db_session, driver_phone))
    start = (datetime.now(UTC) + timedelta(days=2)).isoformat()
    r = await client.post("/api/v1/bookings", headers=ch, json={"driver_id": pid, "booking_type": "HOURLY", "start_time": start, "hours": 2, "pickup_address": "12 MG Road"})
    assert r.status_code == 201, r.text
    return r.json()


NEW = [
    ("get", "/drivers/live"), ("get", "/bookings"), ("get", f"/bookings/{'0' * 8}-0000-0000-0000-{'0' * 12}"),
    ("get", f"/users/{'0' * 8}-0000-0000-0000-{'0' * 12}"),
    ("patch", f"/drivers/{'0' * 8}-0000-0000-0000-{'0' * 12}/answers/hourly_rate"),
]


@pytest.mark.parametrize("method,path", NEW)
async def test_every_new_endpoint_is_401_without_a_token_and_403_for_non_admins(client, method, path):
    kwargs = {"json": {"status": "APPROVED"}} if method == "patch" else {}
    assert (await getattr(client, method)(f"{A}{path}", **kwargs)).status_code == 401
    for headers in (await register_customer(client), (await register_driver(client))[0]):
        assert (await getattr(client, method)(f"{A}{path}", headers=headers, **kwargs)).status_code == 403


async def test_rejecting_an_answer_sets_the_driver_to_needs_changes(client, db_session):
    admin = await admin_headers(client, db_session)
    h, _ = await signup_driver(client)
    await apply_driver(client, h)
    pid = await profile_id(db_session)
    r = await client.patch(f"{A}/drivers/{pid}/answers/hourly_rate", headers=admin, json={"status": "REJECTED", "note": "Too high"})
    assert r.status_code == 200 and r.json() == {"key": "hourly_rate", "status": "REJECTED", "review_note": "Too high"}
    me = (await client.get("/api/v1/drivers/me", headers=h)).json()
    assert me["verification_status"] == "REJECTED"
    assert next(a for a in me["application"]["answers"] if a["key"] == "hourly_rate")["review_note"] == "Too high"


async def test_answer_decision_validates(client, db_session):
    admin = await admin_headers(client, db_session)
    h, _ = await signup_driver(client)
    await apply_driver(client, h)
    pid = await profile_id(db_session)
    assert (await client.patch(f"{A}/drivers/{pid}/answers/hourly_rate", headers=admin, json={"status": "PENDING"})).status_code == 422
    assert (await client.patch(f"{A}/drivers/{pid}/answers/nope", headers=admin, json={"status": "APPROVED"})).status_code == 404


async def test_driver_list_filters_by_verification_availability_and_needs_update(client, db_session):
    admin = await admin_headers(client, db_session)
    await signup_driver(client, "+919876500010")                      # NOT_SUBMITTED
    await register_driver(client, "+919876500011")                    # PENDING
    await _online(client, db_session, "+919876500012")                # APPROVED + AVAILABLE
    ids = lambda r: {i["phone"] for i in r.json()["items"]}  # noqa: E731
    assert ids(await client.get(f"{A}/drivers", headers=admin, params={"verification": "NOT_SUBMITTED"})) == {"+919876500010"}
    assert ids(await client.get(f"{A}/drivers", headers=admin, params={"availability": "AVAILABLE"})) == {"+919876500012"}
    await client.post(f"{A}/forms/driver/fields", headers=admin, json={"key": "badge_no", "label": "Badge", "field_type": "text", "required": True})
    flagged = ids(await client.get(f"{A}/drivers", headers=admin, params={"needs_update": "true", "verification": "APPROVED"}))
    assert flagged == {"+919876500012"}


async def test_driver_detail_has_answers_needs_update_and_last_seen(client, db_session):
    admin = await admin_headers(client, db_session)
    h = await _online(client, db_session, "+919876500012")
    await client.post(f"{A}/forms/driver/fields", headers=admin, json={"key": "badge_no", "label": "Badge", "field_type": "text", "required": True})
    pid = await profile_id(db_session, "+919876500012")
    d = (await client.get(f"{A}/drivers/{pid}", headers=admin)).json()
    assert set(d["needs_update"]) == {"badge_no", "licence_number", "experience_years", "hourly_rate", "LICENCE", "ID_PROOF"}
    assert d["last_seen"] is not None and d["answers"] == [] and d["email"] is None


async def test_live_drivers_only_fresh_and_active_statuses(client, db_session):
    admin = await admin_headers(client, db_session)
    await _online(client, db_session, "+919876500012")
    r = await client.get(f"{A}/drivers/live", headers=admin)
    assert r.status_code == 200
    [d] = r.json()["drivers"]
    assert d["status"] == "AVAILABLE" and d["name"] == "Ravi Kumar"
    assert (d["latitude"], d["longitude"]) == (NEAR["latitude"], NEAR["longitude"])
    assert set(d) == {"id", "name", "status", "latitude", "longitude", "heading", "speed", "recorded_at"}
    await force_status(db_session, "+919876500012", availability_status="ON_TRIP")
    assert len((await client.get(f"{A}/drivers/live", headers=admin)).json()["drivers"]) == 1


async def test_live_drivers_excludes_offline_stale_and_suspended(client, db_session):
    admin = await admin_headers(client, db_session)
    await _online(client, db_session, "+919876500012")
    await _online(client, db_session, "+919876500013")
    await _online(client, db_session, "+919876500014")
    await force_status(db_session, "+919876500012", availability_status="OFFLINE")
    await force_status(db_session, "+919876500013", availability_status="SUSPENDED")
    [only] = (await client.get(f"{A}/drivers/live", headers=admin)).json()["drivers"]
    pid = await profile_id(db_session, "+919876500014")
    await db_session.execute(text("UPDATE driver_locations SET recorded_at = now() - interval '2 minutes' WHERE driver_id = :d"), {"d": pid})
    await db_session.commit()
    await get_redis().delete(f"driver:location:{pid}")
    assert only["id"] == str(pid)
    assert (await client.get(f"{A}/drivers/live", headers=admin)).json()["drivers"] == []


async def test_deactivated_driver_is_not_on_the_live_map(client, db_session):
    admin = await admin_headers(client, db_session)
    await _online(client, db_session, "+919876500012")
    from app.models.user import User

    await db_session.execute(update(User).where(User.phone == "+919876500012").values(is_active=False))
    await db_session.commit()
    assert (await client.get(f"{A}/drivers/live", headers=admin)).json()["drivers"] == []


async def test_bookings_list_filters_and_bounds(client, db_session):
    admin = await admin_headers(client, db_session)
    b = await _booking(client, db_session)
    r = await client.get(f"{A}/bookings", headers=admin)
    assert r.json()["total"] == 1 and r.json()["items"][0]["id"] == b["id"]
    item = r.json()["items"][0]
    assert item["status"] == "REQUESTED" and item["price_amount"] == "360.00" and item["driver_name"] == "Ravi Kumar" and item["customer_name"] == "Asha Rao"
    assert (await client.get(f"{A}/bookings", headers=admin, params={"status": "COMPLETED"})).json()["total"] == 0
    assert (await client.get(f"{A}/bookings", headers=admin, params={"status": "NOPE"})).status_code == 422
    assert (await client.get(f"{A}/bookings", headers=admin, params={"limit": 101})).status_code == 422
    assert (await client.get(f"{A}/bookings", headers=admin, params={"offset": -1})).status_code == 422
    assert (await client.get(f"{A}/bookings", headers=admin, params={"driver_id": "00000000-0000-0000-0000-000000000000"})).json()["total"] == 0


async def test_booking_detail_and_unknown_booking(client, db_session):
    admin = await admin_headers(client, db_session)
    b = await _booking(client, db_session)
    d = (await client.get(f"{A}/bookings/{b['id']}", headers=admin)).json()
    assert d["pickup_address"] == "12 MG Road" and d["hours"] == 2 and d["driver_phone"] == "+919876500000"
    assert (await client.get(f"{A}/bookings/00000000-0000-0000-0000-000000000000", headers=admin)).status_code == 404


async def test_user_detail_shows_customer_answers_and_driver_link(client, db_session):
    admin = await admin_headers(client, db_session)
    ch = await register_customer(client)
    await client.put("/api/v1/customers/profile", headers=ch, json={"answers": {"default_address": "12 MG Road"}})
    await register_driver(client)
    users = (await client.get(f"{A}/users", headers=admin)).json()["items"]
    customer = next(u for u in users if u["role"] == "customer")
    driver = next(u for u in users if u["role"] == "driver")
    c = (await client.get(f"{A}/users/{customer['id']}", headers=admin)).json()
    assert c["customer_answers"] == {"default_address": "12 MG Road"} and c["driver_id"] is None
    d = (await client.get(f"{A}/users/{driver['id']}", headers=admin)).json()
    assert d["driver_id"] == str(await profile_id(db_session)) and d["customer_answers"] == {}


async def test_user_search_finds_email_only_accounts(client, db_session):
    admin = await admin_headers(client, db_session)
    await client.post("/api/v1/auth/customer/register", json={"full_name": "Mail Only", "email": "mail.only@example.com", "password": "password123"})
    r = await client.get(f"{A}/users", headers=admin, params={"q": "mail.only@"})
    assert [u["full_name"] for u in r.json()["items"]] == ["Mail Only"]
    assert r.json()["items"][0]["email"] == "mail.only@example.com"


async def test_stats_counts(client, db_session):
    admin = await admin_headers(client, db_session)
    await signup_driver(client, "+919876500010")
    await register_driver(client, "+919876500011")
    await _online(client, db_session, "+919876500012")
    await _booking(client, db_session, "+919876500013")
    s = (await client.get(f"{A}/stats", headers=admin)).json()
    assert s["drivers"]["NOT_SUBMITTED"] == 1 and s["drivers"]["PENDING"] == 1 and s["drivers"]["APPROVED"] == 2
    assert s["online_now"] == 1 and s["bookings_today"] == 1
    assert s["needs_update"] == 2 and s["rejected"] == 0 and s["not_submitted"] == 1


async def test_search_with_percent_and_underscore_is_literal(client, db_session):
    admin = await admin_headers(client, db_session)
    await register_customer(client)
    for q in ("%", "_", "%%%%", "a_c"):
        assert (await client.get(f"{A}/users", headers=admin, params={"q": q})).json()["total"] == 0, q
