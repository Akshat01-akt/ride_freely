import uuid
from datetime import datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import CheckConstraint, DateTime, Enum, ForeignKey, Integer, Numeric, SmallInteger, String, func, text
from sqlalchemy.dialects.postgresql import UUID, ExcludeConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class BookingType(StrEnum):
    HOURLY = "HOURLY"
    FULL_DAY = "FULL_DAY"


class BookingStatus(StrEnum):
    REQUESTED = "REQUESTED"
    ACCEPTED = "ACCEPTED"
    REJECTED = "REJECTED"
    CANCELLED = "CANCELLED"
    EXPIRED = "EXPIRED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"


# Bookings in these states hold the driver's time slot.
ACTIVE_STATES = (BookingStatus.REQUESTED, BookingStatus.ACCEPTED, BookingStatus.IN_PROGRESS)


def _enum(cls: type[StrEnum]) -> Enum:
    return Enum(cls, native_enum=False, length=20, values_callable=lambda e: [m.value for m in e])


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = (
        # The database, not application code, guarantees a driver is never double-booked.
        # tstzrange is half-open ([start, end)), so back-to-back slots do not collide.
        ExcludeConstraint(
            ("driver_id", "="),
            (text("tstzrange(start_time, end_time)"), "&&"),
            using="gist",
            where=text("status IN ('REQUESTED', 'ACCEPTED', 'IN_PROGRESS')"),
            name="bookings_no_driver_overlap",
        ),
        CheckConstraint("rating BETWEEN 1 AND 5", name="bookings_rating_range"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    customer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("customer_profiles.id", ondelete="CASCADE"), index=True)
    driver_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("driver_profiles.id", ondelete="CASCADE"), index=True)
    booking_type: Mapped[BookingType] = mapped_column(_enum(BookingType))
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    end_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    hours: Mapped[int] = mapped_column(Integer)
    pickup_address: Mapped[str] = mapped_column(String(300))
    notes: Mapped[str | None] = mapped_column(String(500), nullable=True)
    price_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    status: Mapped[BookingStatus] = mapped_column(
        _enum(BookingStatus), default=BookingStatus.REQUESTED, server_default="REQUESTED"
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    rating: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    rated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
