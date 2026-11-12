import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.models.document import DriverDocument
from app.models.driver import DriverProfile
from app.models.user import User


async def _driver(db_session, phone="+919876500001") -> DriverProfile:
    user = User(full_name="D", phone=phone, password_hash="x", role="driver")
    db_session.add(user)
    await db_session.flush()
    profile = DriverProfile(user_id=user.id, licence_number="DL1", experience_years=1, hourly_rate=100)
    db_session.add(profile)
    await db_session.flush()
    return profile


async def test_driver_locations_has_a_spatial_index(db_session):
    rows = (await db_session.execute(text(
        "select indexdef from pg_indexes where tablename='driver_locations'"))).scalars().all()
    assert any("gist" in r.lower() for r in rows)


async def test_one_document_per_driver_and_type(db_session):
    p = await _driver(db_session)
    for _ in range(2):
        db_session.add(DriverDocument(driver_id=p.id, doc_type="LICENCE", file_key=str(uuid.uuid4()),
                                      content_type="image/png", size_bytes=10))
    with pytest.raises(IntegrityError):
        await db_session.commit()


async def test_document_defaults_to_pending(db_session):
    p = await _driver(db_session)
    db_session.add(DriverDocument(driver_id=p.id, doc_type="ID_PROOF", file_key="k", content_type="image/png", size_bytes=1))
    await db_session.commit()
    status = (await db_session.execute(text("select status from driver_documents"))).scalar_one()
    assert status == "PENDING"
