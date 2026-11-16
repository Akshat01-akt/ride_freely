from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models.driver import DriverProfile
from tests.helpers import (ANSWERS, admin_headers, apply_driver, approved_driver, force_status, profile_id,
                           register_customer, signup_driver, upload_document)

API = "/api/v1"


async def _me(client, h):
    return (await client.get(f"{API}/drivers/me", headers=h)).json()


async def _live_booking(client, db_session):
    """An approved driver (with application answers and both documents) holding an ACCEPTED booking."""
    ch = await register_customer(client)
    dh = await approved_driver(client, db_session)
    assert (await apply_driver(client, dh)).status_code == 200  # first answers: no change to approval
    pid = str(await profile_id(db_session))
    start = (datetime.now(UTC) + timedelta(days=2)).isoformat()
    b = await client.post(f"{API}/bookings", headers=ch, json={"driver_id": pid, "booking_type": "HOURLY", "start_time": start, "hours": 2, "pickup_address": "12 MG Road"})
    assert b.status_code == 201, b.text
    assert (await client.post(f"{API}/bookings/{b.json()['id']}/accept", headers=dh)).status_code == 200
    return dh, pid


async def test_a_driver_without_core_details_cannot_be_approved(client, db_session):
    admin = await admin_headers(client, db_session)
    h, _ = await signup_driver(client)
    for key in ("LICENCE", "ID_PROOF"):
        await upload_document(client, h, key)
    for d in (await _me(client, h))["application"]["documents"]:
        await client.patch(f"{API}/admin/documents/{d['id']}", headers=admin, json={"status": "APPROVED"})
    pid = await profile_id(db_session)
    await client.patch(f"{API}/admin/drivers/{pid}/verification", headers=admin, json={"status": "REJECTED"})
    r = await client.patch(f"{API}/admin/drivers/{pid}/verification", headers=admin, json={"status": "APPROVED"})
    assert r.status_code == 409
    db_session.expire_all()
    assert (await db_session.execute(select(DriverProfile.verification_status))).scalar_one() == "REJECTED"


async def test_rejecting_a_document_or_answer_is_refused_while_a_booking_is_live(client, db_session):
    admin = await admin_headers(client, db_session)
    dh, pid = await _live_booking(client, db_session)
    me = await _me(client, dh)
    licence = next(d for d in me["application"]["documents"] if d["doc_type"] == "LICENCE")
    assert (await client.patch(f"{API}/admin/documents/{licence['id']}", headers=admin, json={"status": "REJECTED"})).status_code == 409
    assert (await client.patch(f"{API}/admin/drivers/{pid}/answers/licence_number", headers=admin, json={"status": "REJECTED"})).status_code == 409
    assert (await _me(client, dh))["verification_status"] == "APPROVED"


async def test_editing_details_or_replacing_a_document_is_refused_while_a_booking_is_live(client, db_session):
    dh, _ = await _live_booking(client, db_session)
    r = await client.post(f"{API}/drivers/application", headers=dh, json={"answers": {"hourly_rate": "250"}})
    assert r.status_code == 409 and "booking" in r.json()["detail"].lower()
    assert (await upload_document(client, dh, "LICENCE")).status_code == 409
    assert (await _me(client, dh))["verification_status"] == "APPROVED"


@pytest.mark.parametrize(
    "field,bad",
    [("licence_number", "ab"), ("licence_number", "x" * 51), ("hourly_rate", "0.001"), ("hourly_rate", "1.234"),
     ("hourly_rate", "100000"), ("hourly_rate", "99999999.99")],
)
async def test_core_values_keep_the_old_registration_limits(client, field, bad):
    h, _ = await signup_driver(client)
    r = await apply_driver(client, h, **{field: bad})
    assert r.status_code == 422, (field, bad)


async def test_core_values_at_the_limits_are_accepted(client):
    h, _ = await signup_driver(client)
    r = await apply_driver(client, h, licence_number="x" * 50, hourly_rate="99999.99")
    assert r.status_code == 200, r.text


async def test_answering_a_new_required_question_keeps_an_approved_driver_bookable(client, db_session):
    admin = await admin_headers(client, db_session)
    h = await approved_driver(client, db_session)
    await apply_driver(client, h)
    await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json={"key": "badge_no", "label": "Badge", "field_type": "text", "required": True})
    await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json={"key": "POLICE_CHECK", "label": "Police check", "field_type": "document", "required": True})
    await force_status(db_session, availability_status="AVAILABLE")
    assert (await upload_document(client, h, "POLICE_CHECK")).status_code == 201
    assert (await client.post(f"{API}/drivers/application", headers=h, json={"answers": {"badge_no": "B-1"}})).status_code == 200
    me = await _me(client, h)
    assert me["verification_status"] == "APPROVED" and me["availability_status"] == "AVAILABLE"
    assert me["application"]["needs_update"] == []


async def test_changing_an_existing_answer_still_sends_an_approved_driver_back(client, db_session):
    h = await approved_driver(client, db_session)
    await apply_driver(client, h)
    assert (await client.post(f"{API}/drivers/application", headers=h, json={"answers": {"hourly_rate": "999"}})).status_code == 200
    assert (await _me(client, h))["verification_status"] == "PENDING"
