import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.document import DocStatus, DocType, DriverDocument
from app.services.storage import FileStorage

MAX_BYTES = 5 * 1024 * 1024

_SIGNATURES = {
    "image/png": (b"\x89PNG\r\n\x1a\n",),
    "image/jpeg": (b"\xff\xd8\xff",),
    "application/pdf": (b"%PDF-",),
}


class UnsupportedFile(Exception):
    pass


class FileTooLarge(Exception):
    pass


def validate_upload(content_type: str | None, data: bytes) -> str:
    """Return the verified content type. The declared type must be allowed AND match the file's own header."""
    if len(data) > MAX_BYTES:
        raise FileTooLarge
    signatures = _SIGNATURES.get(content_type or "")
    if signatures is None or not data.startswith(signatures):
        raise UnsupportedFile
    return content_type  # type: ignore[return-value]


async def save_document(
    session: AsyncSession, storage: FileStorage, driver_id: uuid.UUID, doc_type: DocType, content_type: str, data: bytes
) -> DriverDocument:
    key = f"{driver_id}/{uuid.uuid4()}"
    await storage.save(key, data)
    existing = await session.scalar(
        select(DriverDocument).where(DriverDocument.driver_id == driver_id, DriverDocument.doc_type == doc_type)
    )
    old_key = None
    if existing is None:
        doc = DriverDocument(driver_id=driver_id, doc_type=doc_type, file_key=key, content_type=content_type, size_bytes=len(data))
        session.add(doc)
    else:
        doc, old_key = existing, existing.file_key
        doc.file_key, doc.content_type, doc.size_bytes = key, content_type, len(data)
        doc.status, doc.review_note = DocStatus.PENDING, None
    try:
        await session.commit()
    except Exception:
        await session.rollback()
        await storage.delete(key)
        raise
    if old_key:
        await storage.delete(old_key)
    await session.refresh(doc)
    return doc
