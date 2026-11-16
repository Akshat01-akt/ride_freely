import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models.driver import DriverProfile
from app.models.user import User

from .helpers import admin_headers, approved_driver, force_status, register_customer, register_driver
from .test_bookings_api import DPHONE, URL as BOOKINGS, create, profile_id, setup

A = "/api/v1/admin"


@pytest.mark.parametrize(
    ("method", "path"),
    [("get", "/stats"), ("get", "/drivers"), ("get", f"/drivers/{uuid.uuid4()}"), ("get", "/users"),
     ("patch", f"/users/{uuid.uuid4()}/active")],
)
async def test_every_new_endpoint_needs_an_admin(client, db_session, method, path):
    ch = await register_customer(client)
    kwargs = {"json": {"active": False}} if method == "patch" else {}
    assert (await getattr(client, method)(A + path, **kwargs)).status_code == 401
    assert (await getattr(client, method)(A + path, headers=ch, **kwargs)).status_code == 403


async def test_stats_count_users_drivers_and_documents(client, db_session):
    ah = await admin_headers(client, db_session)
    await register_customer(client)
    await register_driver(client, phone="+919876500010")
    await approved_driver(client, db_session, "+919876500011")
    s = (await client.get(f"{A}/stats", headers=ah)).json()
    assert s["customers"] == 1
    assert s["drivers"] == {"total": 2, "NOT_SUBMITTED": 0, "PENDING": 1, "APPROVED": 1, "REJECTED": 0}
    assert s["pending_documents"] == 0
    assert s["admins"] == 1


async def test_driver_list_filters_searches_and_pages(client, db_session):
    ah = await admin_headers(client, db_session)
    await register_driver(client, phone="+919876500010", full_name="Ravi Kumar")
    await register_driver(client, phone="+919876500011", full_name="Sunil Verma")
    await approved_driver(client, db_session, "+919876500012")
    body = (await client.get(f"{A}/drivers", headers=ah)).json()
    assert body["total"] == 3 and len(body["items"]) == 3
    item = body["items"][0]
    assert {"id", "full_name", "phone", "verification_status", "availability_status", "rating", "hourly_rate", "is_active", "created_at"} <= set(item)
    assert (await client.get(f"{A}/drivers", headers=ah, params={"verification": "APPROVED"})).json()["total"] == 1
    assert (await client.get(f"{A}/drivers", headers=ah, params={"q": "sunil"})).json()["total"] == 1
    assert (await client.get(f"{A}/drivers", headers=ah, params={"q": "500011"})).json()["total"] == 1
    page = (await client.get(f"{A}/drivers", headers=ah, params={"limit": 2, "offset": 2})).json()
    assert page["total"] == 3 and len(page["items"]) == 1


@pytest.mark.parametrize("q", ["%", "_", "'; drop table users;--", "x" * 500, "\\"])
async def test_search_text_is_safe(client, db_session, q):
    ah = await admin_headers(client, db_session)
    await register_driver(client)
    r = await client.get(f"{A}/drivers", headers=ah, params={"q": q})
    assert r.status_code == 200
    assert r.json()["total"] == 0  # wildcards are matched literally, not as patterns


@pytest.mark.parametrize("params", [{"limit": 0}, {"limit": 101}, {"offset": -1}, {"verification": "NOPE"}])
async def test_bad_paging_or_filter_is_422(client, db_session, params):
    ah = await admin_headers(client, db_session)
    assert (await client.get(f"{A}/drivers", headers=ah, params=params)).status_code == 422
    assert (await client.get(f"{A}/users", headers=ah, params=params)).status_code in (200, 422)


async def test_driver_detail_has_documents_and_account_state(client, db_session):
    ah = await admin_headers(client, db_session)
    dh, _ = await register_driver(client)
    await client.post("/api/v1/drivers/documents", headers=dh, data={"doc_type": "LICENCE"},
                      files={"file": ("a.png", b"\x89PNG\r\n\x1a\n" + b"0" * 20, "image/png")})
    pid = await profile_id(db_session)
    d = (await client.get(f"{A}/drivers/{pid}", headers=ah)).json()
    assert d["full_name"] == "Ravi Kumar" and d["licence_number"] == "DL-0420110012345"
    assert d["is_active"] is True and d["completed_trips"] == 0
    [doc] = d["documents"]
    assert doc["doc_type"] == "LICENCE" and doc["status"] == "PENDING" and doc["content_type"] == "image/png"
    assert {"id", "size_bytes", "updated_at"} <= set(doc)
    assert (await client.get(f"{A}/drivers/{uuid.uuid4()}", headers=ah)).status_code == 404


async def test_user_list_filters_by_role_and_search(client, db_session):
    ah = await admin_headers(client, db_session)
    await register_customer(client)
    await register_driver(client)
    everyone = (await client.get(f"{A}/users", headers=ah)).json()
    assert everyone["total"] == 3
    assert "password_hash" not in str(everyone)
    assert (await client.get(f"{A}/users", headers=ah, params={"role": "customer"})).json()["total"] == 1
    assert (await client.get(f"{A}/users", headers=ah, params={"role": "admin"})).json()["total"] == 1
    assert (await client.get(f"{A}/users", headers=ah, params={"q": "asha"})).json()["total"] == 1
    assert (await client.get(f"{A}/users", headers=ah, params={"role": "robot"})).status_code == 422


async def _uid(db_session, phone):
    return str(await db_session.scalar(select(User.id).where(User.phone == phone)))


async def test_deactivating_a_user_blocks_login_and_tokens_and_reactivating_restores(client, db_session):
    ah = await admin_headers(client, db_session)
    ch = await register_customer(client)
    uid = await _uid(db_session, "+919876543210")
    r = await client.patch(f"{A}/users/{uid}/active", json={"active": False}, headers=ah)
    assert r.status_code == 200 and r.json()["is_active"] is False
    assert (await client.get("/api/v1/bookings", headers=ch)).status_code == 401
    login = await client.post("/api/v1/auth/customer/login", json={"phone": "+919876543210", "password": "password123"})
    assert login.status_code == 401
    await client.patch(f"{A}/users/{uid}/active", json={"active": True}, headers=ah)
    assert (await client.get("/api/v1/bookings", headers=ch)).status_code == 200


async def test_deactivating_a_driver_takes_them_offline(client, db_session):
    ah = await admin_headers(client, db_session)
    await approved_driver(client, db_session)
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    await client.patch(f"{A}/users/{await _uid(db_session, DPHONE)}/active", json={"active": False}, headers=ah)
    db_session.expire_all()
    status_ = await db_session.scalar(select(DriverProfile.availability_status))
    assert status_ == "OFFLINE"


async def test_admins_and_self_cannot_be_deactivated(client, db_session):
    ah = await admin_headers(client, db_session)
    me = await _uid(db_session, "+919000000001")
    assert (await client.patch(f"{A}/users/{me}/active", json={"active": False}, headers=ah)).status_code == 409
    from app.services.auth_service import create_admin

    await create_admin(db_session, "Second", "+919000000002", "admin-password-2")
    other = await _uid(db_session, "+919000000002")
    assert (await client.patch(f"{A}/users/{other}/active", json={"active": False}, headers=ah)).status_code == 409


async def test_a_user_with_a_live_booking_cannot_be_deactivated(client, db_session):
    ah = await admin_headers(client, db_session)
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    await client.post(f"{BOOKINGS}/{b['id']}/accept", headers=dh)
    for phone in (DPHONE, "+919876543210"):
        r = await client.patch(f"{A}/users/{await _uid(db_session, phone)}/active", json={"active": False}, headers=ah)
        assert r.status_code == 409


async def test_unknown_user_is_404_and_bad_body_422(client, db_session):
    ah = await admin_headers(client, db_session)
    assert (await client.patch(f"{A}/users/{uuid.uuid4()}/active", json={"active": False}, headers=ah)).status_code == 404
    assert (await client.patch(f"{A}/users/{uuid.uuid4()}/active", json={}, headers=ah)).status_code == 422
    assert (await client.patch(f"{A}/users/nope/active", json={"active": False}, headers=ah)).status_code == 422


# ---- review fixes ----

async def test_deactivating_a_customer_cancels_their_unanswered_requests(client, db_session):
    ah = await admin_headers(client, db_session)
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    r = await client.patch(f"{A}/users/{await _uid(db_session, '+919876543210')}/active", json={"active": False}, headers=ah)
    assert r.status_code == 200
    # the driver can no longer accept a request from someone who cannot log in
    assert (await client.post(f"{BOOKINGS}/{b['id']}/accept", headers=dh)).status_code == 409
    seen = (await client.get(f"{BOOKINGS}/{b['id']}", headers=dh)).json()
    assert seen["status"] == "CANCELLED"


async def test_deactivating_a_driver_cancels_their_unanswered_requests(client, db_session):
    ah = await admin_headers(client, db_session)
    ch, dh, pid = await setup(client, db_session)
    b = await create(client, ch, pid)
    await client.patch(f"{A}/users/{await _uid(db_session, DPHONE)}/active", json={"active": False}, headers=ah)
    assert (await client.get(f"{BOOKINGS}/{b['id']}", headers=ch)).json()["status"] == "CANCELLED"


async def test_a_running_trip_blocks_deactivation_even_after_its_window_passed(client, db_session):
    from sqlalchemy import update

    from app.models.booking import Booking

    ah = await admin_headers(client, db_session)
    ch, dh, pid = await setup(client, db_session)
    await force_status(db_session, DPHONE, availability_status="AVAILABLE")
    b = await create(client, ch, pid, start_time=datetime.now(UTC).isoformat(), hours=1)
    for action in ("accept", "start"):
        await client.post(f"{BOOKINGS}/{b['id']}/{action}", headers=dh)
    past = datetime.now(UTC) - timedelta(hours=3)
    await db_session.execute(update(Booking).values(start_time=past, end_time=past + timedelta(hours=1)))
    await db_session.commit()
    for phone in (DPHONE, "+919876543210"):
        r = await client.patch(f"{A}/users/{await _uid(db_session, phone)}/active", json={"active": False}, headers=ah)
        assert r.status_code == 409
