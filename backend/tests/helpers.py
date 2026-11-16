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


async def signup_driver(client, phone="+919876500000", **over) -> tuple[dict, dict]:
    """A driver exactly as the app creates one: name, mobile number and password, nothing else (NOT_SUBMITTED)."""
    r = await client.post("/api/v1/auth/driver/register", json={"full_name": DRIVER["full_name"], "phone": phone, "password": DRIVER["password"], **over})
    assert r.status_code == 201, r.text
    return bearer(r.json()), r.json()


async def register_driver(client, phone="+919876500000", **over) -> tuple[dict, dict]:
    """A driver whose application was already submitted (PENDING, details filled in), for tests that are not about onboarding."""
    from sqlalchemy import update

    from app.core.database import SessionLocal
    from app.models.driver import DriverProfile, VerificationStatus
    from app.models.user import User

    details = {k: over.pop(k, DRIVER[k]) for k in ("licence_number", "experience_years", "hourly_rate")}
    headers, tokens = await signup_driver(client, phone, **over)
    async with SessionLocal() as session:
        user_id = (await session.execute(__import__("sqlalchemy").select(User.id).where(User.phone == phone))).scalar_one()
        await session.execute(
            update(DriverProfile).where(DriverProfile.user_id == user_id).values(verification_status=VerificationStatus.PENDING, **details)
        )
        await session.commit()
    return headers, tokens


PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64
ANSWERS = {"licence_number": "DL-0420110012345", "experience_years": "6", "hourly_rate": "180.00"}


async def upload_document(client, headers, key="LICENCE"):
    return await client.post("/api/v1/drivers/documents", headers=headers, data={"doc_type": key}, files={"file": ("d.png", PNG, "image/png")})


async def apply_driver(client, headers, docs=("LICENCE", "ID_PROOF"), **answers):
    """Upload the documents and submit the application form; returns the submit response."""
    for key in docs:
        assert (await upload_document(client, headers, key)).status_code == 201
    return await client.post("/api/v1/drivers/application", headers=headers, json={"answers": {**ANSWERS, **answers}})


async def profile_id(db_session, phone="+919876500000"):
    from sqlalchemy import select

    from app.models.driver import DriverProfile
    from app.models.user import User

    return (await db_session.execute(select(DriverProfile.id).join(User, User.id == DriverProfile.user_id).where(User.phone == phone))).scalar_one()


async def register_customer(client, phone="+919876543210") -> dict:
    r = await client.post("/api/v1/auth/customer/register", json={**CUSTOMER, "phone": phone})
    assert r.status_code == 201, r.text
    return bearer(r.json())


async def force_status(db_session, phone="+919876500000", **values):
    """Set profile columns directly (verification_status / availability_status) for test setup."""
    from sqlalchemy import update

    from app.models.driver import DriverProfile
    from app.models.user import User

    sub = (await db_session.execute(__import__("sqlalchemy").select(User.id).where(User.phone == phone))).scalar_one()
    await db_session.execute(update(DriverProfile).where(DriverProfile.user_id == sub).values(**values))
    await db_session.commit()


async def approved_driver(client, db_session, phone="+919876500000"):
    headers, tokens = await register_driver(client, phone=phone)
    await force_status(db_session, phone, verification_status="APPROVED")
    return headers
