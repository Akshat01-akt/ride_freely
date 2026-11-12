import uuid

from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.document import DocStatus, DocType, DriverDocument
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.services.location_service import clear_location

REQUIRED_DOCS = (DocType.LICENCE, DocType.ID_PROOF)


class NotFound(Exception):
    pass


class RequirementsNotMet(Exception):
    pass


async def _profile(session: AsyncSession, driver_id: uuid.UUID) -> DriverProfile:
    profile = await session.get(DriverProfile, driver_id)
    if profile is None:
        raise NotFound
    return profile


async def review_document(session: AsyncSession, doc_id: uuid.UUID, status: DocStatus, note: str | None) -> DriverDocument:
    doc = await session.get(DriverDocument, doc_id)
    if doc is None:
        raise NotFound
    doc.status, doc.review_note = status, note
    await session.commit()
    return doc


async def set_verification(
    session: AsyncSession, redis: Redis, driver_id: uuid.UUID, status: VerificationStatus
) -> DriverProfile:
    profile = await _profile(session, driver_id)
    if status == VerificationStatus.APPROVED:
        approved = set(
            await session.scalars(
                select(DriverDocument.doc_type).where(
                    DriverDocument.driver_id == driver_id, DriverDocument.status == DocStatus.APPROVED
                )
            )
        )
        if not set(REQUIRED_DOCS) <= approved:
            raise RequirementsNotMet
    profile.verification_status = status
    if status != VerificationStatus.APPROVED and profile.availability_status != AvailabilityStatus.OFFLINE:
        profile.availability_status = AvailabilityStatus.OFFLINE
        await clear_location(session, redis, driver_id)
    await session.commit()
    return profile


async def set_suspension(session: AsyncSession, redis: Redis, driver_id: uuid.UUID, suspended: bool) -> DriverProfile:
    profile = await _profile(session, driver_id)
    if suspended:
        profile.availability_status = AvailabilityStatus.SUSPENDED
        await clear_location(session, redis, driver_id)
    elif profile.availability_status == AvailabilityStatus.SUSPENDED:
        profile.availability_status = AvailabilityStatus.OFFLINE
    await session.commit()
    return profile
