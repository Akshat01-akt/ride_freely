import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.booking import ACTIVE_STATES, Booking, BookingStatus, BookingType
from app.models.customer import CustomerProfile
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
    await session.commit()  # release the expiry row locks before taking others, so two requests cannot deadlock

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

    # Lock the customer's row so two simultaneous requests cannot both pass the limit.
    await session.scalar(select(CustomerProfile.id).where(CustomerProfile.id == customer_id).with_for_update())
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


class NotFound(BookingError):
    pass


class IllegalTransition(BookingError):
    pass


def _mine(stmt, customer_id: uuid.UUID | None, driver_id: uuid.UUID | None):
    if customer_id is not None:
        return stmt.where(Booking.customer_id == customer_id)
    return stmt.where(Booking.driver_id == driver_id)


async def list_bookings(
    session: AsyncSession, *, customer_id: uuid.UUID | None = None, driver_id: uuid.UUID | None = None
) -> list[Booking]:
    await expire_stale(session, customer_id=customer_id, driver_id=driver_id)
    await session.commit()
    stmt = _mine(select(Booking), customer_id, driver_id).order_by(Booking.created_at.desc()).limit(100)
    return list((await session.scalars(stmt)).all())


async def _locked(
    session: AsyncSession, booking_id: uuid.UUID, customer_id: uuid.UUID | None, driver_id: uuid.UUID | None
) -> Booking:
    """The caller's own booking with its row locked, so two simultaneous actions run one after the other."""
    stmt = _mine(select(Booking).where(Booking.id == booking_id), customer_id, driver_id)
    booking = await session.scalar(stmt.with_for_update().execution_options(populate_existing=True))
    if booking is None:
        raise NotFound
    now = datetime.now(UTC)
    if booking.status == BookingStatus.REQUESTED and (booking.expires_at < now or booking.end_time < now):
        booking.status = BookingStatus.EXPIRED
        await session.commit()
    return booking


async def get_booking(
    session: AsyncSession, booking_id: uuid.UUID, *, customer_id: uuid.UUID | None = None, driver_id: uuid.UUID | None = None
) -> Booking:
    booking = await _locked(session, booking_id, customer_id, driver_id)
    await session.commit()  # release the row lock
    return booking


async def _move(
    session: AsyncSession,
    booking_id: uuid.UUID,
    *,
    allowed: tuple[BookingStatus, ...],
    to: BookingStatus,
    customer_id: uuid.UUID | None = None,
    driver_id: uuid.UUID | None = None,
) -> Booking:
    booking = await _locked(session, booking_id, customer_id, driver_id)
    if booking.status not in allowed:
        await session.rollback()
        raise IllegalTransition
    booking.status = to
    return booking


async def _driver_in_good_standing(session: AsyncSession, driver_id: uuid.UUID) -> DriverProfile:
    """The locked driver profile, or IllegalTransition if they are no longer approved or are suspended."""
    driver = await session.scalar(
        select(DriverProfile).where(DriverProfile.id == driver_id).with_for_update().execution_options(populate_existing=True)
    )
    user = await session.get(User, driver.user_id)
    if (
        driver.verification_status != VerificationStatus.APPROVED
        or driver.availability_status == AvailabilityStatus.SUSPENDED
        or not user.is_active
    ):
        await session.rollback()
        raise IllegalTransition
    return driver


async def cancel(session: AsyncSession, booking_id: uuid.UUID, customer_id: uuid.UUID) -> Booking:
    booking = await _move(
        session, booking_id, allowed=(BookingStatus.REQUESTED, BookingStatus.ACCEPTED),
        to=BookingStatus.CANCELLED, customer_id=customer_id,
    )
    await session.commit()
    return booking


async def accept(session: AsyncSession, booking_id: uuid.UUID, driver_id: uuid.UUID) -> Booking:
    booking = await _move(
        session, booking_id, allowed=(BookingStatus.REQUESTED,), to=BookingStatus.ACCEPTED, driver_id=driver_id
    )
    await _driver_in_good_standing(session, driver_id)
    await session.commit()
    return booking


async def reject(session: AsyncSession, booking_id: uuid.UUID, driver_id: uuid.UUID) -> Booking:
    booking = await _move(
        session, booking_id, allowed=(BookingStatus.REQUESTED,), to=BookingStatus.REJECTED, driver_id=driver_id
    )
    await session.commit()
    return booking


async def start(session: AsyncSession, booking_id: uuid.UUID, driver_id: uuid.UUID) -> Booking:
    booking = await _move(
        session, booking_id, allowed=(BookingStatus.ACCEPTED,), to=BookingStatus.IN_PROGRESS, driver_id=driver_id
    )
    driver = await _driver_in_good_standing(session, driver_id)
    now = datetime.now(UTC)
    already_driving = await session.scalar(
        select(func.count()).select_from(Booking).where(
            Booking.driver_id == driver_id, Booking.status == BookingStatus.IN_PROGRESS, Booking.id != booking.id
        )
    )
    # Only inside the booked window (from 15 minutes before), and never two trips at once.
    if booking.start_time - BOOK_NOW_WINDOW > now or booking.end_time <= now or already_driving:
        await session.rollback()
        raise IllegalTransition
    driver.availability_status = AvailabilityStatus.ON_TRIP
    await session.commit()
    return booking


async def complete(session: AsyncSession, booking_id: uuid.UUID, driver_id: uuid.UUID) -> Booking:
    booking = await _move(
        session, booking_id, allowed=(BookingStatus.IN_PROGRESS,), to=BookingStatus.COMPLETED, driver_id=driver_id
    )
    driver = await session.get(DriverProfile, driver_id, with_for_update=True, populate_existing=True)
    # GPS sharing stopped during the trip, so the driver goes online again themselves.
    if driver.availability_status == AvailabilityStatus.ON_TRIP:
        driver.availability_status = AvailabilityStatus.OFFLINE
    await session.commit()
    return booking


async def describe(session: AsyncSession, bookings: list[Booking]) -> list[dict]:
    """Bookings as API dicts. The other party's phone number appears only while the booking is ACCEPTED or IN_PROGRESS."""
    if not bookings:
        return []
    drivers = {
        d.id: (d, u)
        for d, u in (
            await session.execute(
                select(DriverProfile, User).join(User, User.id == DriverProfile.user_id).where(
                    DriverProfile.id.in_({b.driver_id for b in bookings})
                )
            )
        ).all()
    }
    customers = {
        c.id: u
        for c, u in (
            await session.execute(
                select(CustomerProfile, User).join(User, User.id == CustomerProfile.user_id).where(
                    CustomerProfile.id.in_({b.customer_id for b in bookings})
                )
            )
        ).all()
    }
    out = []
    for b in bookings:
        share = b.status in (BookingStatus.ACCEPTED, BookingStatus.IN_PROGRESS)
        d_user = drivers[b.driver_id][1]
        c_user = customers[b.customer_id]
        out.append(
            {
                "id": b.id,
                "status": b.status,
                "booking_type": b.booking_type,
                "start_time": b.start_time,
                "end_time": b.end_time,
                "hours": b.hours,
                "price_amount": f"{b.price_amount:.2f}",
                "pickup_address": b.pickup_address,
                "notes": b.notes,
                "expires_at": b.expires_at,
                "driver": {"id": b.driver_id, "name": d_user.full_name, **({"phone": d_user.phone} if share else {})},
                "customer": {"name": c_user.full_name, **({"phone": c_user.phone} if share else {})},
            }
        )
    return out
