from sqlalchemy import select

from app.models.customer import CustomerProfile
from tests.helpers import admin_headers, register_customer

API = "/api/v1"


async def _put(client, headers, answers):
    return await client.put(f"{API}/customers/profile", headers=headers, json={"answers": answers})


async def test_customer_can_save_profile_answers(client):
    h = await register_customer(client)
    r = await _put(client, h, {"default_address": "12 MG Road, Bengaluru"})
    assert r.status_code == 200, r.text
    me = (await client.get(f"{API}/customers/me", headers=h)).json()
    assert me["profile"]["answers"] == {"default_address": "12 MG Road, Bengaluru"}
    assert me["profile"]["needs_update"] == []


async def test_default_address_is_synced_to_the_profile_row(client, db_session):
    h = await register_customer(client)
    await _put(client, h, {"default_address": "  12 MG Road  "})
    db_session.expire_all()
    assert (await db_session.execute(select(CustomerProfile.default_address))).scalar_one() == "12 MG Road"
    assert (await client.get(f"{API}/customers/me", headers=h)).json()["default_address"] == "12 MG Road"


async def test_unknown_key_is_422(client):
    r = await _put(client, await register_customer(client), {"shoe_size": "9"})
    assert r.status_code == 422 and r.json()["detail"][0]["loc"][-1] == "shoe_size"


async def test_empty_or_too_long_value_is_422(client):
    h = await register_customer(client)
    for bad in ("", "   ", "x" * 501):
        assert (await _put(client, h, {"default_address": bad})).status_code == 422, bad


async def test_only_customers_can_save(client):
    from tests.helpers import register_driver

    headers, _ = await register_driver(client)
    assert (await _put(client, headers, {"default_address": "x"})).status_code == 403


async def test_booking_works_without_a_profile_and_a_new_required_field_only_flags(client, db_session):
    admin = await admin_headers(client, db_session)
    h = await register_customer(client)
    r = await client.post(f"{API}/admin/forms/customer/fields", headers=admin,
                          json={"key": "landmark", "label": "Landmark", "field_type": "text", "required": True})
    assert r.status_code == 201
    me = (await client.get(f"{API}/customers/me", headers=h)).json()
    assert me["profile"]["answers"] == {} and me["profile"]["needs_update"] == ["landmark"]
    assert (await client.get(f"{API}/drivers/nearby?latitude=12.9&longitude=77.6", headers=h)).status_code == 200


async def test_saving_again_replaces_a_value_and_keeps_the_others(client):
    h = await register_customer(client)
    await _put(client, h, {"default_address": "A"})
    await _put(client, h, {"default_address": "B"})
    assert (await client.get(f"{API}/customers/me", headers=h)).json()["profile"]["answers"] == {"default_address": "B"}
