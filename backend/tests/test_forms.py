import uuid

from tests.helpers import admin_headers, register_customer, register_driver

API = "/api/v1"
NEW_FIELD = {"key": "vehicle_types", "label": "Vehicles you can drive", "field_type": "choice", "required": False,
             "choices": ["Hatchback", "Sedan", "SUV"]}


async def _driver_form(client, headers):
    r = await client.get(f"{API}/forms/driver", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def test_seeded_driver_form_has_core_fields_and_documents(client):
    headers, _ = await register_driver(client)
    form = await _driver_form(client, headers)
    keys = {f["key"]: f for f in form["fields"]}
    assert list(keys)[:3] == ["licence_number", "experience_years", "hourly_rate"]
    assert keys["hourly_rate"]["field_type"] == "number" and keys["hourly_rate"]["required"] is True
    assert {k: keys[k]["field_type"] for k in ("LICENCE", "ID_PROOF", "PHOTO")} == {k: "document" for k in ("LICENCE", "ID_PROOF", "PHOTO")}
    assert keys["PHOTO"]["required"] is False
    assert form["version"] >= 1


async def test_public_form_needs_login(client):
    assert (await client.get(f"{API}/forms/driver")).status_code == 401
    assert (await client.get(f"{API}/forms/nonsense", headers=await register_customer(client))).status_code == 422


async def test_non_admin_cannot_edit_forms(client, db_session):
    headers, _ = await register_driver(client)
    for call in (
        client.get(f"{API}/admin/forms/driver", headers=headers),
        client.post(f"{API}/admin/forms/driver/fields", headers=headers, json=NEW_FIELD),
    ):
        assert (await call).status_code == 403
    assert (await client.get(f"{API}/admin/forms/driver")).status_code == 401


async def test_add_field_bumps_version_and_appears_for_drivers(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await register_driver(client)
    before = (await _driver_form(client, headers))["version"]
    r = await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json=NEW_FIELD)
    assert r.status_code == 201, r.text
    form = await _driver_form(client, headers)
    assert form["version"] == before + 1
    assert form["fields"][-1]["key"] == "vehicle_types"
    assert form["fields"][-1]["choices"] == ["Hatchback", "Sedan", "SUV"]


async def test_duplicate_key_is_409(client, db_session):
    admin = await admin_headers(client, db_session)
    assert (await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json=NEW_FIELD)).status_code == 201
    assert (await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json=NEW_FIELD)).status_code == 409


async def test_key_must_be_slug(client, db_session):
    admin = await admin_headers(client, db_session)
    for bad in ("Bad Key!", "1abc", "a", "x" * 50, "has-dash"):
        r = await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json={**NEW_FIELD, "key": bad})
        assert r.status_code == 422, bad


async def test_choice_field_requires_choices(client, db_session):
    admin = await admin_headers(client, db_session)
    for choices in (None, ["only-one"], ["a", "a"]):
        r = await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json={**NEW_FIELD, "choices": choices})
        assert r.status_code == 422, choices
    r = await client.post(f"{API}/admin/forms/driver/fields", headers=admin,
                          json={**NEW_FIELD, "field_type": "text", "choices": ["a", "b"]})
    assert r.status_code == 422


async def test_customer_form_cannot_have_document_fields(client, db_session):
    admin = await admin_headers(client, db_session)
    r = await client.post(f"{API}/admin/forms/customer/fields", headers=admin,
                          json={"key": "id_card", "label": "ID card", "field_type": "document"})
    assert r.status_code == 422


async def test_cannot_delete_deactivate_retype_or_loosen_core_field(client, db_session):
    admin = await admin_headers(client, db_session)
    fields = {f["key"]: f for f in (await client.get(f"{API}/admin/forms/driver", headers=admin)).json()["fields"]}
    rate = fields["hourly_rate"]["id"]
    assert (await client.delete(f"{API}/admin/forms/driver/fields/{rate}", headers=admin)).status_code == 409
    for patch in ({"is_active": False}, {"field_type": "text"}, {"required": False}):
        assert (await client.patch(f"{API}/admin/forms/driver/fields/{rate}", headers=admin, json=patch)).status_code == 409, patch
    r = await client.patch(f"{API}/admin/forms/driver/fields/{rate}", headers=admin, json={"label": "Rate per hour (INR)"})
    assert r.status_code == 200 and r.json()["label"] == "Rate per hour (INR)"


async def test_delete_is_soft_and_hides_from_public_form(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await register_driver(client)
    created = (await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json=NEW_FIELD)).json()
    assert (await client.delete(f"{API}/admin/forms/driver/fields/{created['id']}", headers=admin)).status_code == 204
    assert "vehicle_types" not in [f["key"] for f in (await _driver_form(client, headers))["fields"]]
    all_fields = (await client.get(f"{API}/admin/forms/driver", headers=admin)).json()["fields"]
    gone = next(f for f in all_fields if f["key"] == "vehicle_types")
    assert gone["is_active"] is False


async def test_field_of_other_role_or_unknown_id_is_404(client, db_session):
    admin = await admin_headers(client, db_session)
    created = (await client.post(f"{API}/admin/forms/driver/fields", headers=admin, json=NEW_FIELD)).json()
    assert (await client.patch(f"{API}/admin/forms/customer/fields/{created['id']}", headers=admin, json={"label": "x"})).status_code == 404
    assert (await client.patch(f"{API}/admin/forms/driver/fields/{uuid.uuid4()}", headers=admin, json={"label": "x"})).status_code == 404


async def test_reorder(client, db_session):
    admin = await admin_headers(client, db_session)
    headers, _ = await register_driver(client)
    fields = (await client.get(f"{API}/admin/forms/driver", headers=admin)).json()["fields"]
    ids = [f["id"] for f in fields]
    r = await client.put(f"{API}/admin/forms/driver/order", headers=admin, json={"ids": list(reversed(ids))})
    assert r.status_code == 200, r.text
    keys = [f["key"] for f in (await _driver_form(client, headers))["fields"]]
    assert keys[0] == "PHOTO" and keys[-1] == "licence_number"
    assert (await client.put(f"{API}/admin/forms/driver/order", headers=admin, json={"ids": ids[:-1]})).status_code == 422


async def test_database_seed_matches_default_fields(client, db_session):
    from sqlalchemy import select

    from app.models.form import FormField
    from app.services.form_service import DEFAULT_FIELDS

    rows = (await db_session.execute(select(FormField.role, FormField.key, FormField.field_type, FormField.required, FormField.is_core))).all()
    assert sorted(rows) == sorted((f["role"], f["key"], f["field_type"], f["required"], f["is_core"]) for f in DEFAULT_FIELDS)
