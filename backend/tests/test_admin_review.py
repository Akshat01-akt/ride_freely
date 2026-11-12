from sqlalchemy import select, text, update

from app.core.redis import get_redis
from app.models.driver import AvailabilityStatus, DriverProfile
from tests.helpers import admin_headers, register_customer, register_driver

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64


async def _upload(client, headers, doc_type):
    r = await client.post("/api/v1/drivers/documents", headers=headers, data={"doc_type": doc_type}, files={"file": ("a.png", PNG, "image/png")})
    assert r.status_code == 201
    return r.json()["id"]


async def _driver_with_docs(client, phone="+919876500000"):
    headers, _ = await register_driver(client, phone=phone)
    lic = await _upload(client, headers, "LICENCE")
    idp = await _upload(client, headers, "ID_PROOF")
    return headers, lic, idp


async def _profile_id(db_session, phone="+919876500000"):
    row = await db_session.execute(text("select dp.id from driver_profiles dp join users u on u.id=dp.user_id where u.phone=:p"), {"p": phone})
    return str(row.scalar_one())


async def test_admin_sees_pending_drivers_with_their_documents(client, db_session):
    admin = await admin_headers(client, db_session)
    await _driver_with_docs(client)
    r = await client.get("/api/v1/admin/drivers/pending", headers=admin)
    assert r.status_code == 200
    [d] = r.json()
    assert d["full_name"] == "Ravi Kumar" and d["licence_number"]
    assert sorted(x["doc_type"] for x in d["documents"]) == ["ID_PROOF", "LICENCE"]


async def test_admin_endpoints_reject_drivers_customers_and_anonymous(client, db_session):
    dh, lic, _ = await _driver_with_docs(client)
    ch = await register_customer(client)
    pid = await _profile_id(db_session)
    calls = [
        ("get", "/api/v1/admin/drivers/pending", None),
        ("get", f"/api/v1/admin/documents/{lic}/file", None),
        ("patch", f"/api/v1/admin/documents/{lic}", {"status": "APPROVED"}),
        ("patch", f"/api/v1/admin/drivers/{pid}/verification", {"status": "APPROVED"}),
        ("patch", f"/api/v1/admin/drivers/{pid}/suspension", {"suspended": True}),
    ]
    for method, url, body in calls:
        for headers, code in ((dh, 403), (ch, 403), ({}, 401)):
            r = await client.request(method, url, headers=headers, json=body)
            assert r.status_code == code, (method, url, code, r.status_code)


async def test_admin_can_download_the_uploaded_file(client, db_session):
    admin = await admin_headers(client, db_session)
    _, lic, _ = await _driver_with_docs(client)
    r = await client.get(f"/api/v1/admin/documents/{lic}/file", headers=admin)
    assert r.status_code == 200 and r.content == PNG and r.headers["content-type"] == "image/png"


async def test_cannot_approve_a_driver_without_both_required_documents_approved(client, db_session):
    admin = await admin_headers(client, db_session)
    _, lic, idp = await _driver_with_docs(client)
    pid = await _profile_id(db_session)
    url = f"/api/v1/admin/drivers/{pid}/verification"
    assert (await client.patch(url, headers=admin, json={"status": "APPROVED"})).status_code == 409
    await client.patch(f"/api/v1/admin/documents/{lic}", headers=admin, json={"status": "APPROVED"})
    assert (await client.patch(url, headers=admin, json={"status": "APPROVED"})).status_code == 409
    await client.patch(f"/api/v1/admin/documents/{idp}", headers=admin, json={"status": "APPROVED"})
    assert (await client.patch(url, headers=admin, json={"status": "APPROVED"})).status_code == 200


async def test_approved_driver_leaves_the_pending_list_and_sees_the_status(client, db_session):
    admin = await admin_headers(client, db_session)
    dh, lic, idp = await _driver_with_docs(client)
    pid = await _profile_id(db_session)
    for d in (lic, idp):
        await client.patch(f"/api/v1/admin/documents/{d}", headers=admin, json={"status": "APPROVED"})
    await client.patch(f"/api/v1/admin/drivers/{pid}/verification", headers=admin, json={"status": "APPROVED"})
    assert (await client.get("/api/v1/admin/drivers/pending", headers=admin)).json() == []
    assert (await client.get("/api/v1/drivers/me", headers=dh)).json()["verification_status"] == "APPROVED"


async def test_rejecting_a_document_records_the_note_for_the_driver(client, db_session):
    admin = await admin_headers(client, db_session)
    dh, lic, _ = await _driver_with_docs(client)
    r = await client.patch(f"/api/v1/admin/documents/{lic}", headers=admin, json={"status": "REJECTED", "note": "Photo is blurry"})
    assert r.status_code == 200
    docs = (await client.get("/api/v1/drivers/documents", headers=dh)).json()
    licence = next(d for d in docs if d["doc_type"] == "LICENCE")
    assert licence["status"] == "REJECTED" and licence["review_note"] == "Photo is blurry"


async def test_pending_is_not_a_valid_review_decision_and_unknown_ids_are_404(client, db_session):
    admin = await admin_headers(client, db_session)
    _, lic, _ = await _driver_with_docs(client)
    assert (await client.patch(f"/api/v1/admin/documents/{lic}", headers=admin, json={"status": "PENDING"})).status_code == 422
    missing = "00000000-0000-0000-0000-000000000000"
    assert (await client.patch(f"/api/v1/admin/documents/{missing}", headers=admin, json={"status": "APPROVED"})).status_code == 404
    assert (await client.patch(f"/api/v1/admin/drivers/{missing}/verification", headers=admin, json={"status": "REJECTED"})).status_code == 404


async def _make_online(db_session, pid):
    await db_session.execute(update(DriverProfile).where(DriverProfile.id == pid).values(availability_status=AvailabilityStatus.AVAILABLE))
    await db_session.execute(text("insert into driver_locations (driver_id, location) values (:d, ST_SetSRID(ST_MakePoint(80.33, 26.45), 4326)::geography)"), {"d": pid})
    await db_session.commit()
    await get_redis().set(f"driver:location:{pid}", "{}", ex=30)


async def test_rejecting_or_suspending_takes_an_online_driver_offline_and_removes_location(client, db_session):
    admin = await admin_headers(client, db_session)
    await _driver_with_docs(client)
    pid = await _profile_id(db_session)
    await _make_online(db_session, pid)
    r = await client.patch(f"/api/v1/admin/drivers/{pid}/verification", headers=admin, json={"status": "REJECTED", "note": "Licence expired"})
    assert r.status_code == 200
    db_session.expire_all()
    profile = (await db_session.execute(select(DriverProfile))).scalar_one()
    assert profile.availability_status == AvailabilityStatus.OFFLINE
    assert await get_redis().get(f"driver:location:{pid}") is None
    assert (await db_session.execute(text("select count(*) from driver_locations"))).scalar_one() == 0


async def test_suspension_blocks_then_unsuspending_returns_driver_offline(client, db_session):
    admin = await admin_headers(client, db_session)
    await _driver_with_docs(client)
    pid = await _profile_id(db_session)
    await _make_online(db_session, pid)
    await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", headers=admin, json={"suspended": True})
    db_session.expire_all()
    assert (await db_session.execute(select(DriverProfile.availability_status))).scalar_one() == AvailabilityStatus.SUSPENDED
    assert await get_redis().get(f"driver:location:{pid}") is None
    await client.patch(f"/api/v1/admin/drivers/{pid}/suspension", headers=admin, json={"suspended": False})
    db_session.expire_all()
    assert (await db_session.execute(select(DriverProfile.availability_status))).scalar_one() == AvailabilityStatus.OFFLINE
