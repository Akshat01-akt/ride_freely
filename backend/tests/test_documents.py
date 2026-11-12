import os
from pathlib import Path

from sqlalchemy import select, update

from app.models.document import DocStatus, DriverDocument
from tests.helpers import register_customer, register_driver

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 64
PDF = b"%PDF-1.4\n" + b"0" * 64
UPLOADS = Path(os.environ["UPLOAD_DIR"])


def _files(data=PNG, name="licence.png", ctype="image/png"):
    return {"file": (name, data, ctype)}


async def _upload(client, headers, doc_type="LICENCE", **kw):
    return await client.post("/api/v1/drivers/documents", headers=headers, data={"doc_type": doc_type}, files=_files(**kw))


async def test_driver_uploads_a_document_and_it_starts_pending(client):
    headers, _ = await register_driver(client)
    r = await _upload(client, headers)
    assert r.status_code == 201
    body = r.json()
    assert body["doc_type"] == "LICENCE" and body["status"] == "PENDING"
    listed = (await client.get("/api/v1/drivers/documents", headers=headers)).json()
    assert [d["doc_type"] for d in listed] == ["LICENCE"]


async def test_jpeg_and_pdf_are_accepted(client):
    headers, _ = await register_driver(client)
    assert (await _upload(client, headers, "ID_PROOF", data=PDF, name="id.pdf", ctype="application/pdf")).status_code == 201
    assert (await _upload(client, headers, "PHOTO", data=JPEG, name="me.jpg", ctype="image/jpeg")).status_code == 201


async def test_wrong_declared_type_is_rejected(client):
    headers, _ = await register_driver(client)
    r = await _upload(client, headers, data=b"hello", name="a.txt", ctype="text/plain")
    assert r.status_code == 415


async def test_content_that_does_not_match_the_declared_type_is_rejected(client):
    headers, _ = await register_driver(client)
    r = await _upload(client, headers, data=b"<script>alert(1)</script>", name="x.png", ctype="image/png")
    assert r.status_code == 415


async def test_oversized_file_is_rejected(client):
    headers, _ = await register_driver(client)
    r = await _upload(client, headers, data=PNG + b"0" * (5 * 1024 * 1024))
    assert r.status_code == 413


async def test_unknown_document_type_is_rejected(client):
    headers, _ = await register_driver(client)
    r = await _upload(client, headers, doc_type="PASSPORT")
    assert r.status_code == 422


async def test_traversal_filename_never_escapes_the_upload_dir(client, db_session):
    headers, _ = await register_driver(client)
    r = await _upload(client, headers, name="../../../../tmp/evil.png")
    assert r.status_code == 201
    doc = (await db_session.execute(select(DriverDocument))).scalar_one()
    assert ".." not in doc.file_key and not doc.file_key.startswith("/")
    stored = (UPLOADS / doc.file_key).resolve()
    assert stored.is_file() and UPLOADS.resolve() in stored.parents


async def test_reupload_replaces_the_file_and_resets_approval(client, db_session):
    headers, _ = await register_driver(client)
    await _upload(client, headers)
    first = (await db_session.execute(select(DriverDocument))).scalar_one()
    old_key = first.file_key
    await db_session.execute(update(DriverDocument).values(status=DocStatus.APPROVED, review_note="ok"))
    await db_session.commit()
    r = await _upload(client, headers, data=JPEG, name="new.jpg", ctype="image/jpeg")
    assert r.status_code == 201 and r.json()["status"] == "PENDING"
    db_session.expire_all()
    rows = (await db_session.execute(select(DriverDocument))).scalars().all()
    assert len(rows) == 1 and rows[0].file_key != old_key and rows[0].review_note is None
    assert not (UPLOADS / old_key).exists()


async def test_each_driver_only_sees_their_own_documents(client):
    a, _ = await register_driver(client, phone="+919876500001")
    b, _ = await register_driver(client, phone="+919876500002")
    await _upload(client, a)
    assert (await client.get("/api/v1/drivers/documents", headers=b)).json() == []


async def test_customers_and_anonymous_cannot_upload(client):
    customer = await register_customer(client)
    assert (await _upload(client, customer)).status_code == 403
    assert (await client.post("/api/v1/drivers/documents", data={"doc_type": "LICENCE"}, files=_files())).status_code == 401
