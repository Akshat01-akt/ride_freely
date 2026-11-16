import pytest

from app.services.auth_service import IdentifierTaken, create_admin
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
    with pytest.raises(IdentifierTaken):
        await create_admin(db_session, "Other", ADMIN["phone"], ADMIN["password"])
    with pytest.raises(ValueError):
        await create_admin(db_session, "Weak", "+919000000002", "short")


async def test_admin_can_be_created_with_an_email_only_and_log_in_by_it(client, db_session):
    await create_admin(db_session, "Mail Admin", None, "admin-password-1", email="Boss@Example.com")
    r = await client.post("/api/v1/auth/admin/login", json={"identifier": "boss@example.com", "password": "admin-password-1"})
    assert r.status_code == 200


async def test_admin_needs_a_phone_or_an_email_and_emails_are_unique(db_session):
    with pytest.raises(ValueError):
        await create_admin(db_session, "Nobody", None, "admin-password-1")
    await create_admin(db_session, "Admin A", None, "admin-password-1", email="a@example.com")
    with pytest.raises(IdentifierTaken):
        await create_admin(db_session, "Admin B", None, "admin-password-1", email="A@EXAMPLE.com")


async def test_cli_creates_an_admin_with_an_email(db_session, capsys):
    from sqlalchemy import select

    from app import cli
    from app.models.user import Role, User

    assert await cli._create_admin("Cli Admin", None, "cli@example.com", "admin-password-1") == 0
    assert "cli@example.com" in capsys.readouterr().out
    db_session.expire_all()
    user = (await db_session.execute(select(User).where(User.email_normalized == "cli@example.com"))).scalar_one()
    assert user.role == Role.ADMIN and user.phone is None
    assert await cli._create_admin("Again", None, "CLI@example.com", "admin-password-1") == 1


async def test_cli_rejects_when_neither_phone_nor_email_is_given(capsys):
    from app import cli

    assert await cli._create_admin("Nobody", None, None, "admin-password-1") == 2
    assert "email" in capsys.readouterr().err.lower()
