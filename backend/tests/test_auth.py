from sqlalchemy import select, update

from app.models.customer import CustomerProfile
from app.models.driver import DriverProfile
from app.models.user import User

CUSTOMER = {"full_name": "Asha Rao", "phone": "+919876543210", "password": "password123"}
DRIVER = {
    "full_name": "Ravi Kumar",
    "phone": "+919876500000",
    "password": "password123",
    "licence_number": "DL-0420110012345",
    "experience_years": 6,
    "hourly_rate": "180.00",
}


def bearer(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


async def test_customer_register_login_me(client):
    r = await client.post("/api/v1/auth/customer/register", json=CUSTOMER)
    assert r.status_code == 201
    assert r.json()["token_type"] == "bearer"
    r = await client.post("/api/v1/auth/customer/login", json={"phone": CUSTOMER["phone"], "password": CUSTOMER["password"]})
    assert r.status_code == 200
    me = await client.get("/api/v1/customers/me", headers=bearer(r.json()))
    assert me.status_code == 200
    assert me.json()["full_name"] == "Asha Rao"
    assert me.json()["phone"] == "+919876543210"
    assert "password_hash" not in me.json()


async def test_driver_register_creates_not_submitted_offline_profile(client):
    r = await client.post("/api/v1/auth/driver/register", json=DRIVER)
    assert r.status_code == 201
    me = await client.get("/api/v1/drivers/me", headers=bearer(r.json()))
    assert me.status_code == 200
    body = me.json()
    assert body["verification_status"] == "NOT_SUBMITTED"
    assert body["availability_status"] == "OFFLINE"
    assert body["licence_number"] is None and body["hourly_rate"] is None  # filled in by the application form


async def test_duplicate_phone_returns_409_across_roles(client, db_session):
    assert (await client.post("/api/v1/auth/customer/register", json=CUSTOMER)).status_code == 201
    r = await client.post("/api/v1/auth/driver/register", json={**DRIVER, "phone": CUSTOMER["phone"]})
    assert r.status_code == 409
    drivers = (await db_session.execute(select(DriverProfile))).scalars().all()
    assert drivers == []
    users = (await db_session.execute(select(User))).scalars().all()
    assert len(users) == 1


async def test_customer_token_forbidden_on_drivers_me(client):
    tokens = (await client.post("/api/v1/auth/customer/register", json=CUSTOMER)).json()
    r = await client.get("/api/v1/drivers/me", headers=bearer(tokens))
    assert r.status_code == 403


async def test_driver_token_forbidden_on_customers_me(client):
    tokens = (await client.post("/api/v1/auth/driver/register", json=DRIVER)).json()
    r = await client.get("/api/v1/customers/me", headers=bearer(tokens))
    assert r.status_code == 403


async def test_driver_phone_on_customer_login_returns_401_same_as_wrong_password(client):
    await client.post("/api/v1/auth/driver/register", json=DRIVER)
    wrong_role = await client.post(
        "/api/v1/auth/customer/login", json={"phone": DRIVER["phone"], "password": DRIVER["password"]}
    )
    wrong_pass = await client.post(
        "/api/v1/auth/driver/login", json={"phone": DRIVER["phone"], "password": "nope-nope-nope"}
    )
    unknown = await client.post(
        "/api/v1/auth/driver/login", json={"phone": "+919000000000", "password": "password123"}
    )
    assert wrong_role.status_code == wrong_pass.status_code == unknown.status_code == 401
    assert wrong_role.json() == wrong_pass.json() == unknown.json()


async def test_refresh_issues_new_pair(client):
    tokens = (await client.post("/api/v1/auth/customer/register", json=CUSTOMER)).json()
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    new = r.json()
    me = await client.get("/api/v1/customers/me", headers=bearer(new))
    assert me.status_code == 200


async def test_access_token_rejected_by_refresh_endpoint(client):
    tokens = (await client.post("/api/v1/auth/customer/register", json=CUSTOMER)).json()
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["access_token"]})
    assert r.status_code == 401


async def test_refresh_token_rejected_as_access_token(client):
    tokens = (await client.post("/api/v1/auth/customer/register", json=CUSTOMER)).json()
    r = await client.get(
        "/api/v1/customers/me", headers={"Authorization": f"Bearer {tokens['refresh_token']}"}
    )
    assert r.status_code == 401


async def test_missing_or_malformed_token_returns_401_json(client):
    for headers in ({}, {"Authorization": "Bearer garbage"}):
        r = await client.get("/api/v1/customers/me", headers=headers)
        assert r.status_code == 401
        assert r.json() == {"detail": "Invalid or expired token"}


async def test_inactive_user_cannot_login_or_use_token(client, db_session):
    tokens = (await client.post("/api/v1/auth/customer/register", json=CUSTOMER)).json()
    await db_session.execute(update(User).values(is_active=False))
    await db_session.commit()
    login = await client.post(
        "/api/v1/auth/customer/login", json={"phone": CUSTOMER["phone"], "password": CUSTOMER["password"]}
    )
    assert login.status_code == 401
    me = await client.get("/api/v1/customers/me", headers=bearer(tokens))
    assert me.status_code == 401


async def test_phone_with_spaces_is_normalised(client):
    r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": "98765 43210"})
    assert r.status_code == 201
    me = await client.get("/api/v1/customers/me", headers=bearer(r.json()))
    assert me.json()["phone"] == "+919876543210"


async def test_invalid_phone_returns_422(client):
    for bad in ("abc", "12345", "+91 98765 4321x"):
        r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": bad})
        assert r.status_code == 422, bad


async def test_short_password_returns_422(client):
    r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "password": "short"})
    assert r.status_code == 422


async def test_customer_register_creates_profile_row(client, db_session):
    await client.post("/api/v1/auth/customer/register", json=CUSTOMER)
    profiles = (await db_session.execute(select(CustomerProfile))).scalars().all()
    assert len(profiles) == 1


async def test_leading_zero_and_country_code_variants_normalise_to_one_number(client):
    r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": "09876543210"})
    assert r.status_code == 201
    for variant in ("+91 98765 43210", "919876543210", "9876543210"):
        dup = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": variant})
        assert dup.status_code == 409, variant


async def test_unicode_digits_and_foreign_or_malformed_numbers_are_rejected(client):
    for bad in ("९८७६५४३२१०", "+91 0 9876543210", "+919876543210123", "+1234567890", "5876543210"):
        r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": bad})
        assert r.status_code == 422, bad


async def test_validation_errors_never_echo_submitted_values(client):
    r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "password": "short-pw"[:7]})
    assert r.status_code == 422
    assert "short-p" not in r.text
    assert all(set(e) <= {"loc", "msg", "type"} for e in r.json()["detail"])
