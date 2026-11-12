from app.services.auth_service import create_admin

ADMIN = {"phone": "+919000000001", "password": "admin-password-1"}
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


async def admin_headers(client, db_session) -> dict:
    await create_admin(db_session, "Admin", ADMIN["phone"], ADMIN["password"])
    r = await client.post("/api/v1/auth/admin/login", json=ADMIN)
    assert r.status_code == 200, r.text
    return bearer(r.json())


async def register_driver(client, phone="+919876500000", **over) -> tuple[dict, dict]:
    body = {**DRIVER, "phone": phone, **over}
    r = await client.post("/api/v1/auth/driver/register", json=body)
    assert r.status_code == 201, r.text
    return bearer(r.json()), r.json()


async def register_customer(client, phone="+919876543210") -> dict:
    r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": phone})
    assert r.status_code == 201, r.text
    return bearer(r.json())
