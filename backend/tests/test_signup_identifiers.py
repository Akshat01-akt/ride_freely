from tests.helpers import ADMIN, admin_headers, bearer

BASE = {"full_name": "Asha Rao", "password": "password123"}


async def _register(client, role="customer", **extra):
    return await client.post(f"/api/v1/auth/{role}/register", json={**BASE, **extra})


async def test_register_with_email_only(client):
    r = await _register(client, email="asha@example.com")
    assert r.status_code == 201
    me = await client.get("/api/v1/customers/me", headers=bearer(r.json()))
    assert me.json()["email"] == "asha@example.com"
    assert me.json()["phone"] is None


async def test_register_with_phone_only(client):
    r = await _register(client, phone="9876543210")
    assert r.status_code == 201
    me = await client.get("/api/v1/customers/me", headers=bearer(r.json()))
    assert me.json()["phone"] == "+919876543210"
    assert me.json()["email"] is None


async def test_register_with_neither_is_422(client):
    assert (await _register(client)).status_code == 422


async def test_driver_register_needs_no_licence(client):
    r = await _register(client, "driver", email="ravi@example.com")
    assert r.status_code == 201
    me = await client.get("/api/v1/drivers/me", headers=bearer(r.json()))
    assert me.status_code == 200
    assert me.json()["licence_number"] is None


async def test_duplicate_email_case_insensitive_is_409(client):
    assert (await _register(client, email="Asha@Example.com")).status_code == 201
    r = await _register(client, "driver", email="asha@example.COM")
    assert r.status_code == 409
    assert "already registered" in r.json()["detail"]


async def test_login_by_email_any_case(client):
    await _register(client, email="Asha@Example.com")
    r = await client.post("/api/v1/auth/customer/login", json={"identifier": "ASHA@example.com", "password": "password123"})
    assert r.status_code == 200


async def test_login_by_phone_with_identifier_and_legacy_key(client):
    await _register(client, phone="+919876543210")
    for body in ({"identifier": "98765 43210"}, {"phone": "+919876543210"}):
        r = await client.post("/api/v1/auth/customer/login", json={**body, "password": "password123"})
        assert r.status_code == 200, body


async def test_login_wrong_password_or_unknown_is_401(client):
    await _register(client, email="asha@example.com")
    for ident, pw in (("asha@example.com", "nope-nope-1"), ("nobody@example.com", "password123"), ("garbage", "password123")):
        r = await client.post("/api/v1/auth/customer/login", json={"identifier": ident, "password": pw})
        assert r.status_code == 401, ident


async def test_admin_login_still_works_with_phone(client, db_session):
    assert (await admin_headers(client, db_session))["Authorization"].startswith("Bearer ")
    r = await client.post("/api/v1/auth/admin/login", json={"identifier": ADMIN["phone"], "password": ADMIN["password"]})
    assert r.status_code == 200
