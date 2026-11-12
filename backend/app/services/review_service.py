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


class HasActiveBooking(Exception):
    pass


_BOOKING_STATES = (AvailabilityStatus.RESERVED, AvailabilityStatus.BOOKED, AvailabilityStatus.ON_TRIP)


async def _profile(session: AsyncSession, driver_id: uuid.UUID) -> DriverProfile:
    profile = await session.get(DriverProfile, driver_id)
    if profile is None:
        raise NotFound
    return profile


async def send_back_for_review(session: AsyncSession, redis: Redis, profile: DriverProfile) -> None:
    """Revoke approval: the driver returns to the review queue and, if online, goes offline.

    Only AVAILABLE is touched. SUSPENDED stays suspended, and booking states are left for the booking engine.
    """
    profile.verification_status = VerificationStatus.PENDING
    if profile.availability_status == AvailabilityStatus.AVAILABLE:
        profile.availability_status = AvailabilityStatus.OFFLINE
        await clear_location(session, redis, profile.id)


async def review_document(
    session: AsyncSession, redis: Redis, doc_id: uuid.UUID, status: DocStatus, note: str | None
) -> DriverDocument:
    doc = await session.get(DriverDocument, doc_id)
    if doc is None:
        raise NotFound
    doc.status, doc.review_note = status, note
    if status == DocStatus.REJECTED and doc.doc_type in REQUIRED_DOCS:
        profile = await session.get(DriverProfile, doc.driver_id)
        if profile is not None and profile.verification_status == VerificationStatus.APPROVED:
            await send_back_for_review(session, redis, profile)
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
    if status != VerificationStatus.APPROVED and profile.availability_status == AvailabilityStatus.AVAILABLE:
        profile.availability_status = AvailabilityStatus.OFFLINE
        await clear_location(session, redis, driver_id)
    await session.commit()
    return profile


async def set_suspension(session: AsyncSession, redis: Redis, driver_id: uuid.UUID, suspended: bool) -> DriverProfile:
    profile = await _profile(session, driver_id)
    if suspended:
        if profile.availability_status in _BOOKING_STATES:
            raise HasActiveBooking
        profile.availability_status = AvailabilityStatus.SUSPENDED
        await clear_location(session, redis, driver_id)
    elif profile.availability_status == AvailabilityStatus.SUSPENDED:
        profile.availability_status = AvailabilityStatus.OFFLINE
    await session.commit()
    return profile


class NotApproved(Exception):
    pass


class StateLocked(Exception):
    pass


async def set_availability(
    session: AsyncSession, redis: Redis, profile: DriverProfile, target: AvailabilityStatus
) -> DriverProfile:
    """A driver may only toggle between OFFLINE and AVAILABLE; every other state is owned by the system."""
    if profile.availability_status not in (AvailabilityStatus.OFFLINE, AvailabilityStatus.AVAILABLE):
        raise StateLocked
    if target == AvailabilityStatus.AVAILABLE and profile.verification_status != VerificationStatus.APPROVED:
        raise NotApproved
    profile.availability_status = target
    if target == AvailabilityStatus.OFFLINE:
        await clear_location(session, redis, profile.id)
    await session.commit()
    return profile
