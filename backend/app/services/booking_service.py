import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.booking import ACTIVE_STATES, Booking, BookingStatus, BookingType
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.models.user import User

MAX_HOURLY_HOURS = 12
FULL_DAY_HOURS = 8
REQUEST_TTL = timedelta(minutes=10)
BOOK_NOW_WINDOW = timedelta(minutes=15)
MAX_ADVANCE = timedelta(days=30)
PAST_TOLERANCE = timedelta(minutes=5)  # phone clocks drift; "now" must not be refused
MAX_ACTIVE_PER_CUSTOMER = 3


class BookingError(Exception):
    pass


class InvalidWindow(BookingError):
    pass


class DriverUnavailable(BookingError):
    pass


class SlotTaken(BookingError):
    pass


class TooManyBookings(BookingError):
    pass


async def expire_stale(
    session: AsyncSession, *, driver_id: uuid.UUID | None = None, customer_id: uuid.UUID | None = None
) -> None:
    """Turn unanswered requests (past their deadline, or past their slot) into EXPIRED, freeing the slot."""
    now = datetime.now(UTC)
    stmt = (
        update(Booking)
        .where(Booking.status == BookingStatus.REQUESTED, (Booking.expires_at < now) | (Booking.end_time < now))
        .values(status=BookingStatus.EXPIRED)
    )
    if driver_id is not None:
        stmt = stmt.where(Booking.driver_id == driver_id)
    if customer_id is not None:
        stmt = stmt.where(Booking.customer_id == customer_id)
    await session.execute(stmt)


def _window(booking_type: BookingType, start_time: datetime, hours: int | None, now: datetime) -> tuple[int, datetime]:
    if start_time.tzinfo is None:
        raise InvalidWindow("Start time must include a timezone")
    if start_time < now - PAST_TOLERANCE or start_time > now + MAX_ADVANCE:
        raise InvalidWindow("Start time must be now or within the next 30 days")
    if booking_type == BookingType.FULL_DAY:
        billed = FULL_DAY_HOURS
    else:
        if hours is None or not 1 <= hours <= MAX_HOURLY_HOURS:
            raise InvalidWindow("Hours must be between 1 and 12")
        billed = hours
    return billed, start_time + timedelta(hours=billed)


async def create_booking(
    session: AsyncSession,
    *,
    customer_id: uuid.UUID,
    driver_id: uuid.UUID,
    booking_type: BookingType,
    start_time: datetime,
    hours: int | None,
    pickup_address: str,
    notes: str | None,
) -> Booking:
    now = datetime.now(UTC)
    billed, end_time = _window(booking_type, start_time, hours, now)

    await expire_stale(session, driver_id=driver_id)
    await expire_stale(session, customer_id=customer_id)

    driver = await session.get(DriverProfile, driver_id)
    user = await session.get(User, driver.user_id) if driver else None
    if (
        driver is None
        or user is None
        or not user.is_active
        or driver.verification_status != VerificationStatus.APPROVED
        or driver.availability_status == AvailabilityStatus.SUSPENDED
    ):
        raise DriverUnavailable
    if start_time <= now + BOOK_NOW_WINDOW and driver.availability_status != AvailabilityStatus.AVAILABLE:
        raise DriverUnavailable

    active = await session.scalar(
        select(func.count()).select_from(Booking).where(
            Booking.customer_id == customer_id, Booking.status.in_(ACTIVE_STATES)
        )
    )
    if active >= MAX_ACTIVE_PER_CUSTOMER:
        raise TooManyBookings

    booking = Booking(
        customer_id=customer_id,
        driver_id=driver_id,
        booking_type=booking_type,
        start_time=start_time,
        end_time=end_time,
        hours=billed,
        pickup_address=pickup_address,
        notes=notes,
        price_amount=(driver.hourly_rate * billed).quantize(Decimal("0.01")),
        status=BookingStatus.REQUESTED,
        expires_at=now + REQUEST_TTL,
    )
    session.add(booking)
    try:
        await session.commit()
    except IntegrityError:
        # The exclusion constraint refused an overlapping slot.
        await session.rollback()
        raise SlotTaken from None
    return booking
