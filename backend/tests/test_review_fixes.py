import pytest
from sqlalchemy import select, text

from app.core.redis import get_redis
from app.models.document import DriverDocument
from app.models.driver import DriverProfile
from app.services import document_service, location_service
from tests.helpers import admin_headers, approved_driver, force_status, register_customer, register_driver

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 64
PHONE = "+919876500000"


async def _upload(client, headers, doc_type="LICENCE", data=PNG, ctype="image/png"):
    return await client.post("/api/v1/drivers/documents", headers=headers, data={"doc_type": doc_type}, files={"file": ("a", data, ctype)})


async def _profile(db_session) -> DriverProfile:
    db_session.expire_all()
    return (await db_session.execute(select(DriverProfile))).scalar_one()


async def _live_approved_driver(client, db_session):
    """Approved, AVAILABLE driver with both required documents uploaded and a live location."""
    h, _ = await register_driver(client)
    await _upload(client, h, "LICENCE")
    await _upload(client, h, "ID_PROOF")
    await force_status(db_session, verification_status="APPROVED")
    await client.patch("/api/v1/drivers/availability", headers=h, json={"status": "AVAILABLE"})
    await client.post("/api/v1/locations/update", headers=h, json={"latitude": 26.4589, "longitude": 80.3319})
    return h


@pytest.mark.parametrize("doc_type", ["LICENCE", "ID_PROOF"])
async def test_replacing_a_required_document_sends_an_approved_driver_back_for_review(client, db_session, doc_type):
    admin = await admin_headers(client, db_session)
    h = await _live_approved_driver(client, db_session)
    pid = (await _profile(db_session)).id
    assert (await _upload(client, h, doc_type, JPEG, "image/jpeg")).status_code == 201
    p = await _profile(db_session)
    assert p.verification_status == "PENDING" and p.availability_status == "OFFLINE"
    assert await get_redis().get(f"driver:location:{pid}") is None
    pending = (await client.get("/api/v1/admin/drivers/pending", headers=admin)).json()
    assert [d["id"] for d in pending] == [str(pid)]
    assert (await client.patch("/api/v1/drivers/availability", headers=h, json={"status": "AVAILABLE"})).status_code == 403


async def test_a_rejected_driver_who_uploads_again_returns_to_the_review_queue(client, db_session):
    admin = await admin_headers(client, db_session)
    h, _ = await register_driver(client)
    await _upload(client, h)
    await force_status(db_session, verification_status="REJECTED")
    assert (await client.get("/api/v1/admin/drivers/pending", headers=admin)).json() == []
    await _upload(client, h, "LICENCE", JPEG, "image/jpeg")
    assert (await _profile(db_session)).verification_status == "PENDING"
    assert len((await client.get("/api/v1/admin/drivers/pending", headers=admin)).json()) == 1


async def test_replacing_the_optional_photo_does_not_affect_approval(client, db_session):
    h = await _live_approved_driver(client, db_session)
    await _upload(client, h, "PHOTO")
    await _upload(client, h, "PHOTO", JPEG, "image/jpeg")
    p = await _profile(db_session)
    assert p.verification_status == "APPROVED" and p.availability_status == "AVAILABLE"


async def test_rejecting_a_required_document_revokes_an_approved_driver(client, db_session):
    admin = await admin_headers(client, db_session)
    h = await _live_approved_driver(client, db_session)
    pid = (await _profile(db_session)).id
    doc = (await db_session.execute(select(DriverDocument).where(DriverDocument.doc_type == "LICENCE"))).scalar_one()
    r = await client.patch(f"/api/v1/admin/documents/{doc.id}", headers=admin, json={"status": "REJECTED", "note": "Expired"})
    assert r.status_code == 200
    p = await _profile(db_session)
    assert p.verification_status == "PENDING" and p.availability_status == "OFFLINE"
    assert await get_redis().get(f"driver:location:{pid}") is None


async def test_rejecting_the_optional_photo_leaves_approval_alone(client, db_session):
    admin = await admin_headers(client, db_session)
    h = await _live_approved_driver(client, db_session)
    await _upload(client, h, "PHOTO")
    doc = (await db_session.execute(select(DriverDocument).where(DriverDocument.doc_type == "PHOTO"))).scalar_one()
    await client.patch(f"/api/v1/admin/documents/{doc.id}", headers=admin, json={"status": "REJECTED"})
    assert (await _profile(db_session)).verification_status == "APPROVED"


async def test_rejecting_or_reuploading_never_lifts_a_suspension(client, db_session):
    admin = await admin_headers(client, db_session)
    h = await _live_approved_driver(client, db_session)
    pid = (await _profile(db_session)).id
    await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", headers=admin, json={"suspended": True})
    await client.patch(f"/api/v1/admin/drivers/{pid}/verification", headers=admin, json={"status": "REJECTED"})
    assert (await _profile(db_session)).availability_status == "SUSPENDED"
    await _upload(client, h, "LICENCE", JPEG, "image/jpeg")
    assert (await _profile(db_session)).availability_status == "SUSPENDED"


@pytest.mark.parametrize("state", ["RESERVED", "BOOKED", "ON_TRIP"])
async def test_a_driver_with_an_active_booking_cannot_be_suspended_underneath_it(client, db_session, state):
    admin = await admin_headers(client, db_session)
    await _live_approved_driver(client, db_session)
    pid = (await _profile(db_session)).id
    await force_status(db_session, availability_status=state)
    r = await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", headers=admin, json={"suspended": True})
    assert r.status_code == 409
    assert (await _profile(db_session)).availability_status == state


async def test_rejecting_verification_does_not_clobber_a_booking_state(client, db_session):
    admin = await admin_headers(client, db_session)
    await _live_approved_driver(client, db_session)
    pid = (await _profile(db_session)).id
    await force_status(db_session, availability_status="BOOKED")
    await client.patch(f"/api/v1/admin/drivers/{pid}/verification", headers=admin, json={"status": "REJECTED"})
    assert (await _profile(db_session)).availability_status == "BOOKED"


async def test_a_driver_with_an_expired_position_is_not_listed_even_if_redis_still_has_a_key(client, db_session):
    c = await register_customer(client)
    await _live_approved_driver(client, db_session)
    await db_session.execute(text("update driver_locations set recorded_at = now() - interval '10 minutes'"))
    await db_session.commit()
    r = await client.get("/api/v1/drivers/nearby", headers=c, params={"latitude": 26.4499, "longitude": 80.3319})
    assert r.json()["drivers"] == []


async def test_stale_drivers_nearer_than_a_live_one_do_not_crowd_it_out(client, db_session, monkeypatch):
    monkeypatch.setattr(location_service, "MAX_RESULTS", 1)
    c = await register_customer(client)
    live = await _live_approved_driver(client, db_session)  # ~1 km away, live
    # A second driver, nearer but with an old position.
    h2 = await approved_driver(client, db_session, "+919876500009")
    await client.patch("/api/v1/drivers/availability", headers=h2, json={"status": "AVAILABLE"})
    await client.post("/api/v1/locations/update", headers=h2, json={"latitude": 26.4500, "longitude": 80.3319})
    await db_session.execute(text("update driver_locations set recorded_at = now() - interval '10 minutes' where ST_Y(location::geometry) < 26.451"))
    await db_session.commit()
    drivers = (await client.get("/api/v1/drivers/nearby", headers=c, params={"latitude": 26.4499, "longitude": 80.3319})).json()["drivers"]
    assert len(drivers) == 1 and 900 <= drivers[0]["distance_meters"] <= 1100
    assert live


async def test_distances_are_rounded_so_a_customer_cannot_pinpoint_a_driver(client, db_session):
    c = await register_customer(client)
    await _live_approved_driver(client, db_session)
    [d] = (await client.get("/api/v1/drivers/nearby", headers=c, params={"latitude": 26.4499, "longitude": 80.3319})).json()["drivers"]
    assert d["distance_meters"] % 100 == 0 and d["distance_meters"] >= 100
    # a driver standing right next to the search point still reports a coarse, non-zero distance
    await client.post("/api/v1/locations/update", headers=await approved_driver_headers(client), json={"latitude": 26.4499, "longitude": 80.3319})
    nearest = (await client.get("/api/v1/drivers/nearby", headers=c, params={"latitude": 26.4499, "longitude": 80.3319})).json()["drivers"][0]
    assert nearest["distance_meters"] == 100


async def approved_driver_headers(client):
    r = await client.post("/api/v1/auth/driver/login", json={"phone": PHONE, "password": "password123"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def test_a_concurrent_upload_conflict_is_a_409_and_leaves_no_orphan_file(client, db_session, monkeypatch):
    import os
    from pathlib import Path

    from sqlalchemy.exc import IntegrityError
    from sqlalchemy.ext.asyncio import AsyncSession

    h, _ = await register_driver(client)
    uploads = Path(os.environ["UPLOAD_DIR"])
    before = {p for p in uploads.rglob("*") if p.is_file()}

    async def boom(self):
        raise IntegrityError("insert", {}, Exception("duplicate"))

    monkeypatch.setattr(AsyncSession, "commit", boom)
    r = await _upload(client, h)
    monkeypatch.undo()
    assert r.status_code == 409
    assert {p for p in uploads.rglob("*") if p.is_file()} == before


async def test_admin_downloads_cannot_be_sniffed_or_rendered(client, db_session):
    admin = await admin_headers(client, db_session)
    h, _ = await register_driver(client)
    doc_id = (await _upload(client, h)).json()["id"]
    r = await client.get(f"/api/v1/admin/documents/{doc_id}/file", headers=admin)
    assert r.headers["x-content-type-options"] == "nosniff"
    assert "sandbox" in r.headers["content-security-policy"]
    assert r.headers["content-disposition"].startswith("attachment")
    assert ".png" in r.headers["content-disposition"]
