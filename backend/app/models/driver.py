import uuid
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import Enum, ForeignKey, Integer, Numeric, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class VerificationStatus(StrEnum):
    NOT_SUBMITTED = "NOT_SUBMITTED"
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class AvailabilityStatus(StrEnum):
    OFFLINE = "OFFLINE"
    AVAILABLE = "AVAILABLE"
    RESERVED = "RESERVED"
    BOOKED = "BOOKED"
    ON_TRIP = "ON_TRIP"
    SUSPENDED = "SUSPENDED"


def _enum(cls: type[StrEnum]) -> Enum:
    return Enum(cls, native_enum=False, length=20, values_callable=lambda e: [m.value for m in e])


class DriverProfile(Base):
    __tablename__ = "driver_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    licence_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
    experience_years: Mapped[int | None] = mapped_column(Integer, nullable=True)
    hourly_rate: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    verification_status: Mapped[VerificationStatus] = mapped_column(
        _enum(VerificationStatus), default=VerificationStatus.NOT_SUBMITTED, server_default="NOT_SUBMITTED"
    )
    availability_status: Mapped[AvailabilityStatus] = mapped_column(
        _enum(AvailabilityStatus), default=AvailabilityStatus.OFFLINE, server_default="OFFLINE"
    )
    rating: Mapped[Decimal] = mapped_column(Numeric(3, 2), default=0, server_default="0")
