import pytest

from app.services.auth_service import PhoneAlreadyRegistered, create_admin
from tests.helpers import ADMIN, CUSTOMER, DRIVER, admin_headers, bearer


async def test_admin_can_log_in(client, db_session):
    headers = await admin_headers(client, db_session)
    assert headers["Authorization"].startswith("Bearer ")


async def test_customer_and_driver_credentials_are_rejected_on_admin_login(client):
    await client.post("/api/v1/auth/customer/register", json=CUSTOMER)
    await client.post("/api/v1/auth/driver/register", json=DRIVER)
    for creds in (CUSTOMER, DRIVER):
        r = await client.post("/api/v1/auth/admin/login", json={"phone": creds["phone"], "password": creds["password"]})
        assert r.status_code == 401


async def test_admin_token_is_not_a_customer_or_driver_token(client, db_session):
    headers = await admin_headers(client, db_session)
    assert (await client.get("/api/v1/customers/me", headers=headers)).status_code == 403
    assert (await client.get("/api/v1/drivers/me", headers=headers)).status_code == 403


async def test_admin_login_needs_the_right_password(client, db_session):
    await create_admin(db_session, "Admin", ADMIN["phone"], ADMIN["password"])
    r = await client.post("/api/v1/auth/admin/login", json={"phone": ADMIN["phone"], "password": "wrong-password"})
    assert r.status_code == 401


async def test_create_admin_rejects_duplicate_phone_and_short_password(db_session):
    await create_admin(db_session, "Admin", ADMIN["phone"], ADMIN["password"])
    with pytest.raises(PhoneAlreadyRegistered):
        await create_admin(db_session, "Other", ADMIN["phone"], ADMIN["password"])
    with pytest.raises(ValueError):
        await create_admin(db_session, "Weak", "+919000000002", "short")
