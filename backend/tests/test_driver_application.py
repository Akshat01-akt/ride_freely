import json
import subprocess
import sys

import asyncpg
import pytest
from sqlalchemy import select

from app.models.answer import DriverAnswer
from app.models.document import DocStatus
from app.services import review_service
from tests.conftest import BACKEND, DB_HOST, DB_PORT, PASSWORD, TEST_DB
from tests.helpers import (ANSWERS, admin_headers, apply_driver, force_status, profile_id, register_customer,
                           signup_driver, upload_document)

API = "/api/v1"


async def _me(client, headers):
    r = await client.get(f"{API}/drivers/me", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def _submit(client, headers, answers):
    return await client.post(f"{API}/drivers/application", headers=headers, json={"answers": answers})


def _errors(response) -> dict[str, str]:
    return {e["loc"][-1]: e["msg"] for e in response.json()["detail"]}


async def test_new_driver_starts_not_submitted_and_cannot_go_online(client):
    headers, _ = await signup_driver(client)
    me = await _me(client, headers)
    assert me["verification_status"] == "NOT_SUBMITTED"
    assert me["application"]["status"] == "NOT_SUBMITTED"
    assert me["application"]["answers"] == []
    r = await client.patch(f"{API}/drivers/availability", headers=headers, json={"status": "AVAILABLE"})
    assert r.status_code == 403


async def test_submit_application_moves_to_pending_and_fills_the_profile(client):
    headers, _ = await signup_driver(client)
    r = await apply_driver(client, headers)
    assert r.status_code == 200, r.text
    me = await _me(client, headers)
    assert me["verification_status"] == "PENDING"
    assert me["licence_number"] == "DL-0420110012345" and me["experience_years"] == 6 and float(me["hourly_rate"]) == 180.0
    assert {a["key"]: a["value"] for a in me["application"]["answers"]} == ANSWERS
    assert {d["doc_type"] for d in me["application"]["documents"]} == {"LICENCE", "ID_PROOF"}
    assert me["application"]["needs_update"] == []


async def test_only_drivers_can_submit(client):
    assert (await _submit(client, await register_customer(client), ANSWERS)).status_code == 403


async def test_missing_required_field_is_422_and_names_the_field(client):
    headers, _ = await signup_driver(client)
    await upload_document(client, headers, "LICENCE")
    await upload_document(client, headers, "ID_PROOF")
    r = await _submit(client, headers, {k: v for k, v in ANSWERS.items() if k != "hourly_rate"})
    assert r.status_code == 422
    assert "hourly_rate" in _errors(r)
    assert (await _me(client, headers))["verification_status"] == "NOT_SUBMITTED"


async def test_unknown_key_is_422(client):
    headers, _ = await signup_driver(client)
    r = await apply_driver(client, headers, shoe_size="9")
    assert r.status_code == 422 and "shoe_size" in _errors(r)


@pytest.mark.parametrize(
    "bad",
    [{"experience_years": "abc"}, {"experience_years": "-1"}, {"experience_years": "61"}, {"experience_years": "2.5"},
     {"hourly_rate": "0"}, {"hourly_rate": "-5"}, {"hourly_rate": "nan"}, {"hourly_rate": "1e9"}, {"licence_number": ""},
     {"licence_number": "x" * 501}, {"LICENCE": "not-an-answer"}],
)
async def test_wrong_type_or_range_is_422(client, bad):
    headers, _ = await signup_driver(client)
    r = await apply_driver(client, headers, **bad)
    assert r.status_code == 422, bad
    assert list(bad)[0] in _errors(r)


async def test_submit_without_required_documents_is_422(client):
    headers, _ = await signup_driver(client)
    r = await apply_driver(client, headers, docs=("LICENCE",))
    assert r.status_code == 422 and "ID_PROOF" in _errors(r)


async def test_upload_for_a_document_not_on_the_form_is_422(client):
    headers, _ = await signup_driver(client)
    assert (await upload_document(client, headers, "PASSPORT")).status_code == 422
    assert (await upload_document(client, headers, "licence_number")).status_code == 422


async def test_choice_and_date_fields_are_validated(client, db_session):
    admin = await admin_headers(client, db_session)
    for body in (
        {"key": "vehicle", "label": "Vehicle", "field_type": "choice", "choices": ["Sedan", "SUV"], "required": True},
        {"key": "dob", "label": "Date of birth", "field_type": "date", "required": True},
    ):
        assert (await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json=body)).status_code == 201
    headers, _ = await signup_driver(client)
    for bad in ({"vehicle": "Tank", "dob": "1990-01-01"}, {"vehicle": "SUV", "dob": "31/12/1990"}, {"vehicle": "SUV", "dob": "1990-02-30"}):
        assert (await apply_driver(client, headers, **bad)).status_code == 422, bad
    assert (await apply_driver(client, headers, vehicle="SUV", dob="1990-12-31")).status_code == 200


async def test_pending_driver_is_not_visible_or_bookable(client, db_session):
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    r = await client.patch(f"{API}/drivers/availability", headers=headers, json={"status": "AVAILABLE"})
    assert r.status_code == 403


async def test_admin_cannot_approve_a_driver_who_has_not_applied(client, db_session):
    admin = await admin_headers(client, db_session)
    await signup_driver(client)
    pid = await profile_id(db_session)
    r = await client.patch(f"{API}/admin/drivers/{pid}/verification", headers=admin, json={"status": "APPROVED"})
    assert r.status_code == 409


async def _approve_everything(client, db_session, admin, headers):
    me = await _me(client, headers)
    for d in me["application"]["documents"]:
        assert (await client.patch(f"{API}/admin/documents/{d['id']}", headers=admin, json={"status": "APPROVED"})).status_code == 200
    pid = await profile_id(db_session)
    r = await client.patch(f"{API}/admin/drivers/{pid}/verification", headers=admin, json={"status": "APPROVED"})
    assert r.status_code == 200, r.text
    return pid


async def test_approving_the_driver_approves_their_answers(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    await _approve_everything(client, db_session, admin, headers)
    me = await _me(client, headers)
    assert me["verification_status"] == "APPROVED"
    assert {a["status"] for a in me["application"]["answers"]} == {"APPROVED"}


async def test_rejected_document_sends_the_driver_to_needs_changes(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    licence = next(d for d in (await _me(client, headers))["application"]["documents"] if d["doc_type"] == "LICENCE")
    await client.patch(f"{API}/admin/documents/{licence['id']}", headers=admin, json={"status": "REJECTED", "note": "Blurry"})
    me = await _me(client, headers)
    assert me["verification_status"] == "REJECTED"
    assert next(d for d in me["application"]["documents"] if d["doc_type"] == "LICENCE")["review_note"] == "Blurry"


async def test_resubmit_must_fix_flagged_items_and_only_resets_those(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    pid = await profile_id(db_session)
    await review_service.review_answer(db_session, __import__("app.core.redis", fromlist=["get_redis"]).get_redis(), pid, "hourly_rate", DocStatus.REJECTED, "Too high")
    # untouched flagged answer: refuse
    r = await _submit(client, headers, {"experience_years": "7"})
    assert r.status_code == 422 and "hourly_rate" in _errors(r)
    r = await _submit(client, headers, {"hourly_rate": "150"})
    assert r.status_code == 200, r.text
    me = await _me(client, headers)
    answers = {a["key"]: a for a in me["application"]["answers"]}
    assert me["verification_status"] == "PENDING"
    assert answers["hourly_rate"]["value"] == "150" and answers["hourly_rate"]["status"] == "PENDING"
    assert answers["licence_number"]["value"] == "DL-0420110012345"
    assert float(me["hourly_rate"]) == 150.0


async def test_resubmit_after_document_rejection_requires_a_new_upload(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    licence = next(d for d in (await _me(client, headers))["application"]["documents"] if d["doc_type"] == "LICENCE")
    await client.patch(f"{API}/admin/documents/{licence['id']}", headers=admin, json={"status": "REJECTED"})
    r = await _submit(client, headers, {})
    assert r.status_code == 422 and "LICENCE" in _errors(r)
    assert (await upload_document(client, headers, "LICENCE")).status_code == 201
    assert (await _submit(client, headers, {})).status_code == 200
    assert (await _me(client, headers))["verification_status"] == "PENDING"


async def test_approved_driver_who_edits_goes_back_to_review_and_offline(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    await _approve_everything(client, db_session, admin, headers)
    await force_status(db_session, availability_status="AVAILABLE")
    same = await _submit(client, headers, {"hourly_rate": "180.00"})
    assert same.status_code == 200 and (await _me(client, headers))["verification_status"] == "APPROVED"
    assert (await _submit(client, headers, {"hourly_rate": "220"})).status_code == 200
    me = await _me(client, headers)
    assert me["verification_status"] == "PENDING" and me["availability_status"] == "OFFLINE"


async def test_admin_adds_a_required_field_approved_driver_stays_bookable_and_flagged(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await signup_driver(client)
    await apply_driver(client, headers)
    await _approve_everything(client, db_session, admin, headers)
    await force_status(db_session, availability_status="OFFLINE")
    r = await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json={"key": "badge_no", "label": "Badge number", "field_type": "text", "required": True})
    assert r.status_code == 201
    me = await _me(client, headers)
    assert me["verification_status"] == "APPROVED"
    assert me["application"]["needs_update"] == ["badge_no"]
    assert (await client.patch(f"{API}/drivers/availability", headers=headers, json={"status": "AVAILABLE"})).status_code == 200
    assert (await _submit(client, headers, {"badge_no": "B-1"})).status_code == 200
    assert (await _me(client, headers))["application"]["needs_update"] == []


async def test_inactive_field_answers_are_kept_but_not_listed_as_needed(client, db_session):
    admin = await admin_headers(client, db_session)
    await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json={"key": "badge_no", "label": "Badge", "field_type": "text", "required": True})
    headers, _ = await signup_driver(client)
    assert (await apply_driver(client, headers, badge_no="B-1")).status_code == 200
    fields = (await client.get(f"{API}/admin/forms/driver", headers=admin)).json()["fields"]
    badge = next(f for f in fields if f["key"] == "badge_no")
    await client.delete(f"{API}/admin/forms/driver/fields/{badge['id']}", headers=admin)
    me = await _me(client, headers)
    assert "badge_no" in {a["key"] for a in me["application"]["answers"]}
    assert (await db_session.execute(select(DriverAnswer).where(DriverAnswer.field_key == "badge_no"))).scalar_one().value == "B-1"


async def test_existing_approved_driver_survives_the_migration():
    def alembic(*args):
        subprocess.run([sys.executable, "-m", "alembic", *args], cwd=BACKEND, check=True)

    alembic("downgrade", "0006")
    conn = await asyncpg.connect(user="app_user", password=PASSWORD, host=DB_HOST, port=int(DB_PORT), database=TEST_DB)
    try:
        await conn.execute(
            "INSERT INTO users (id, full_name, phone, password_hash, role) VALUES ('11111111-1111-1111-1111-111111111111', 'Old Driver', '+919811111111', 'x', 'driver')"
        )
        await conn.execute(
            "INSERT INTO driver_profiles (id, user_id, licence_number, experience_years, hourly_rate, verification_status, availability_status) "
            "VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'DL-OLD', 9, 250.00, 'APPROVED', 'OFFLINE')"
        )
        alembic("upgrade", "head")
        status = await conn.fetchval("SELECT verification_status FROM driver_profiles WHERE id = '22222222-2222-2222-2222-222222222222'")
        rows = await conn.fetch("SELECT field_key, value, status FROM driver_answers ORDER BY field_key")
    finally:
        await conn.execute("DELETE FROM users WHERE id = '11111111-1111-1111-1111-111111111111'")
        await conn.close()
    assert status == "APPROVED"
    assert [tuple(r) for r in rows] == [("experience_years", "9", "APPROVED"), ("hourly_rate", "250.00", "APPROVED"), ("licence_number", "DL-OLD", "APPROVED")]
