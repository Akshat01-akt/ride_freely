import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_role
from app.core.database import get_session
from app.models.customer import CustomerProfile
from app.models.driver import DriverProfile
from app.models.user import Role, User
from app.schemas.booking import BookingCreate, BookingOut
from app.services import booking_service as bs

router = APIRouter(prefix="/bookings", tags=["bookings"])


async def _customer(user: User = Depends(require_role(Role.CUSTOMER)), session: AsyncSession = Depends(get_session)) -> CustomerProfile:
    profile = await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id))
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Customer profile not found")
    return profile


async def _driver(user: User = Depends(require_role(Role.DRIVER)), session: AsyncSession = Depends(get_session)) -> DriverProfile:
    profile = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id))
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Driver profile not found")
    return profile


async def _either(
    user: User = Depends(require_role(Role.CUSTOMER, Role.DRIVER)), session: AsyncSession = Depends(get_session)
) -> dict:
    """The caller as {'customer_id': ...} or {'driver_id': ...}, whichever they are."""
    if user.role == Role.CUSTOMER:
        profile = await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id))
        key = "customer_id"
    else:
        profile = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id))
        key = "driver_id"
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profile not found")
    return {key: profile.id}


async def _one(session: AsyncSession, booking) -> dict:
    return (await bs.describe(session, [booking]))[0]


def _translate(exc: bs.BookingError) -> HTTPException:
    if isinstance(exc, bs.NotFound):
        return HTTPException(status.HTTP_404_NOT_FOUND, "Booking not found")
    if isinstance(exc, bs.InvalidWindow):
        return HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(exc))
    messages = {
        bs.DriverUnavailable: "This driver is not available for that time",
        bs.SlotTaken: "The driver already has a booking at that time",
        bs.TooManyBookings: "You already have 3 active bookings. Finish or cancel one first",
        bs.IllegalTransition: "This booking cannot be changed that way right now",
    }
    return HTTPException(status.HTTP_409_CONFLICT, messages.get(type(exc), "Conflict"))


@router.post("", response_model=BookingOut, response_model_exclude_none=True, status_code=status.HTTP_201_CREATED)
async def create(payload: BookingCreate, customer: CustomerProfile = Depends(_customer), session: AsyncSession = Depends(get_session)):
    try:
        booking = await bs.create_booking(
            session,
            customer_id=customer.id,
            driver_id=payload.driver_id,
            booking_type=payload.booking_type,
            start_time=payload.start_time or datetime.now(UTC),
            hours=payload.hours,
            pickup_address=payload.pickup_address,
            notes=payload.notes,
        )
    except bs.BookingError as exc:
        raise _translate(exc) from None
    return await _one(session, booking)


@router.get("", response_model=list[BookingOut], response_model_exclude_none=True)
async def mine(who: dict = Depends(_either), session: AsyncSession = Depends(get_session)):
    return await bs.describe(session, await bs.list_bookings(session, **who))


@router.get("/{booking_id}", response_model=BookingOut, response_model_exclude_none=True)
async def read(booking_id: uuid.UUID, who: dict = Depends(_either), session: AsyncSession = Depends(get_session)):
    try:
        return await _one(session, await bs.get_booking(session, booking_id, **who))
    except bs.BookingError as exc:
        raise _translate(exc) from None


@router.post("/{booking_id}/cancel", response_model=BookingOut, response_model_exclude_none=True)
async def cancel(booking_id: uuid.UUID, customer: CustomerProfile = Depends(_customer), session: AsyncSession = Depends(get_session)):
    try:
        return await _one(session, await bs.cancel(session, booking_id, customer.id))
    except bs.BookingError as exc:
        raise _translate(exc) from None


def _driver_action(name: str):
    action = getattr(bs, name)

    @router.post(f"/{{booking_id}}/{name}", response_model=BookingOut, response_model_exclude_none=True, name=name)
    async def endpoint(booking_id: uuid.UUID, driver: DriverProfile = Depends(_driver), session: AsyncSession = Depends(get_session)):
        try:
            return await _one(session, await action(session, booking_id, driver.id))
        except bs.BookingError as exc:
            raise _translate(exc) from None

    return endpoint


for _name in ("accept", "reject", "start", "complete"):
    _driver_action(_name)
