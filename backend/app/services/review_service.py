import uuid

from redis.asyncio import Redis
from datetime import UTC, datetime

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.booking import Booking, BookingStatus
from app.models.customer import CustomerProfile
from app.models.answer import DriverAnswer
from app.models.document import DocStatus, DriverDocument
from app.models.form import FormField
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.models.user import Role, User
from app.services.location_service import clear_location


async def required_keys(session: AsyncSession, document: bool | None = None) -> set[str]:
    """Keys of the active required fields on the driver form; document=True/False limits to documents / answers."""
    query = select(FormField.key).where(FormField.role == "driver", FormField.is_active, FormField.required)
    if document is not None:
        query = query.where((FormField.field_type == "document") if document else (FormField.field_type != "document"))
    return set(await session.scalars(query))


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


async def send_back_for_review(
    session: AsyncSession, redis: Redis, profile: DriverProfile, to: VerificationStatus = VerificationStatus.PENDING
) -> None:
    """Revoke approval: the driver returns to the review queue (PENDING) or to "needs changes" (REJECTED) and, if online, goes offline.

    Only AVAILABLE is touched. SUSPENDED stays suspended, and booking states are left for the booking engine.
    """
    profile.verification_status = to
    if profile.availability_status == AvailabilityStatus.AVAILABLE:
        profile.availability_status = AvailabilityStatus.OFFLINE
        await clear_location(session, redis, profile.id)


async def review_document(
    session: AsyncSession, redis: Redis, doc_id: uuid.UUID, status: DocStatus, note: str | None
) -> DriverDocument:
    doc = await session.get(DriverDocument, doc_id)
    if doc is None:
        raise NotFound
    revokes = status == DocStatus.REJECTED and doc.doc_type in await required_keys(session, document=True)
    if revokes:
        await _check_can_revoke(session, doc.driver_id)
    doc.status, doc.review_note = status, note
    if revokes:
        await _needs_changes(session, redis, doc.driver_id)
    await session.commit()
    return doc


async def _check_can_revoke(session: AsyncSession, driver_id: uuid.UUID) -> None:
    """Sending a driver back is refused while a customer is counting on an accepted or running booking."""
    profile = await session.get(DriverProfile, driver_id)
    if profile is not None and profile.verification_status in (VerificationStatus.APPROVED, VerificationStatus.PENDING) and await _has_live_booking(session, driver_id):
        raise HasActiveBooking


async def _needs_changes(session: AsyncSession, redis: Redis, driver_id: uuid.UUID) -> None:
    """A required item was rejected: a driver in review or approved goes to "needs changes" until they fix it."""
    profile = await session.get(DriverProfile, driver_id)
    if profile is not None and profile.verification_status in (VerificationStatus.APPROVED, VerificationStatus.PENDING):
        await send_back_for_review(session, redis, profile, to=VerificationStatus.REJECTED)


async def review_answer(
    session: AsyncSession, redis: Redis, driver_id: uuid.UUID, key: str, status: DocStatus, note: str | None
) -> DriverAnswer:
    answer = await session.scalar(select(DriverAnswer).where(DriverAnswer.driver_id == driver_id, DriverAnswer.field_key == key))
    if answer is None:
        raise NotFound
    revokes = status == DocStatus.REJECTED and key in await required_keys(session, document=False)
    if revokes:
        await _check_can_revoke(session, driver_id)
    answer.status, answer.review_note = status, note
    if revokes:
        await _needs_changes(session, redis, driver_id)
    await session.commit()
    return answer


async def _has_live_booking(
    session: AsyncSession, driver_id: uuid.UUID | None = None, customer_id: uuid.UUID | None = None
) -> bool:
    """An accepted or running booking that has not ended yet; the other party is counting on it."""
    owner = (Booking.driver_id == driver_id) if driver_id is not None else (Booking.customer_id == customer_id)
    running_or_upcoming = (
        ((Booking.status == BookingStatus.ACCEPTED) & (Booking.end_time > datetime.now(UTC)))
        | (Booking.status == BookingStatus.IN_PROGRESS)  # a trip nobody has completed is still live
    )
    return (await session.scalar(select(Booking.id).where(owner, running_or_upcoming).limit(1))) is not None


async def set_verification(
    session: AsyncSession, redis: Redis, driver_id: uuid.UUID, status: VerificationStatus
) -> DriverProfile:
    profile = await _profile(session, driver_id)
    if status == VerificationStatus.APPROVED:
        if profile.verification_status == VerificationStatus.NOT_SUBMITTED:
            raise RequirementsNotMet
        approved = set(
            await session.scalars(
                select(DriverDocument.doc_type).where(
                    DriverDocument.driver_id == driver_id, DriverDocument.status == DocStatus.APPROVED
                )
            )
        )
        rejected = await session.scalar(
            select(DriverAnswer.id).where(DriverAnswer.driver_id == driver_id, DriverAnswer.status == DocStatus.REJECTED).limit(1)
        )
        if not await required_keys(session, document=True) <= approved or rejected is not None:
            raise RequirementsNotMet
        if None in (profile.licence_number, profile.experience_years, profile.hourly_rate):
            raise RequirementsNotMet  # pricing and search need the core details
        await session.execute(
            update(DriverAnswer)
            .where(DriverAnswer.driver_id == driver_id, DriverAnswer.status == DocStatus.PENDING)
            .values(status=DocStatus.APPROVED)
        )
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
        # Lock the profile rows so an accept that is running right now finishes before we look.
        driver = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id).with_for_update())
        customer = await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id).with_for_update())
        if driver is not None and await _has_live_booking(session, driver_id=driver.id):
            raise HasActiveBooking
        if customer is not None and await _has_live_booking(session, customer_id=customer.id):
            raise HasActiveBooking
        # Unanswered requests would otherwise be left for someone who can no longer answer or cancel them.
        for profile, column in ((driver, Booking.driver_id), (customer, Booking.customer_id)):
            if profile is not None:
                await session.execute(
                    update(Booking).where(column == profile.id, Booking.status == BookingStatus.REQUESTED).values(status=BookingStatus.CANCELLED)
                )
        if driver is not None and driver.availability_status in (AvailabilityStatus.AVAILABLE, AvailabilityStatus.RESERVED):
            driver.availability_status = AvailabilityStatus.OFFLINE
            await clear_location(session, redis, driver.id)
    user.is_active = active
    await session.commit()
    return user
