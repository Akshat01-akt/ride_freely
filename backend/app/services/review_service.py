import uuid

from redis.asyncio import Redis
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.booking import Booking, BookingStatus
from app.models.customer import CustomerProfile
from app.models.document import DocStatus, DocType, DriverDocument
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.models.user import Role, User
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


async def _has_live_booking(
    session: AsyncSession, driver_id: uuid.UUID | None = None, customer_id: uuid.UUID | None = None
) -> bool:
    """An accepted or running booking that has not ended yet; the other party is counting on it."""
    return (
        await session.scalar(
            select(Booking.id).where(
                (Booking.driver_id == driver_id) if driver_id is not None else (Booking.customer_id == customer_id),
                Booking.status.in_((BookingStatus.ACCEPTED, BookingStatus.IN_PROGRESS)),
                Booking.end_time > datetime.now(UTC),
            ).limit(1)
        )
    ) is not None


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
    if status != VerificationStatus.APPROVED and await _has_live_booking(session, driver_id):
        raise HasActiveBooking
    profile.verification_status = status
    if status != VerificationStatus.APPROVED and profile.availability_status == AvailabilityStatus.AVAILABLE:
        profile.availability_status = AvailabilityStatus.OFFLINE
        await clear_location(session, redis, driver_id)
    await session.commit()
    return profile


async def set_suspension(session: AsyncSession, redis: Redis, driver_id: uuid.UUID, suspended: bool) -> DriverProfile:
    profile = await _profile(session, driver_id)
    if suspended:
        if profile.availability_status in _BOOKING_STATES or await _has_live_booking(session, driver_id):
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


class ProtectedAccount(Exception):
    pass


async def set_user_active(session: AsyncSession, redis: Redis, user_id: uuid.UUID, active: bool) -> User:
    """Turn an account off or on. Off means no login, no refresh and no token works (enforced where tokens are read)."""
    user = await session.get(User, user_id)
    if user is None:
        raise NotFound
    if not active:
        if user.role == Role.ADMIN:
            raise ProtectedAccount
        driver = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id))
        customer = await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id))
        if driver is not None and await _has_live_booking(session, driver_id=driver.id):
            raise HasActiveBooking
        if customer is not None and await _has_live_booking(session, customer_id=customer.id):
            raise HasActiveBooking
        if driver is not None and driver.availability_status in (AvailabilityStatus.AVAILABLE, AvailabilityStatus.RESERVED):
            driver.availability_status = AvailabilityStatus.OFFLINE
            await clear_location(session, redis, driver.id)
    user.is_active = active
    await session.commit()
    return user
