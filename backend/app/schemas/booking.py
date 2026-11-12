import uuid
from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from app.models.booking import BookingStatus, BookingType


def _not_blank(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("Must not be blank")
    return value


Address = Annotated[str, Field(max_length=300), AfterValidator(_not_blank)]


class BookingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    driver_id: uuid.UUID
    booking_type: BookingType
    start_time: datetime | None = None  # missing means "now"
    hours: int | None = None
    pickup_address: Address
    notes: Annotated[str, Field(max_length=500)] | None = None


class PartyOut(BaseModel):
    id: uuid.UUID | None = None
    name: str
    phone: str | None = None


class BookingOut(BaseModel):
    id: uuid.UUID
    status: BookingStatus
    booking_type: BookingType
    start_time: datetime
    end_time: datetime
    hours: int
    price_amount: str
    pickup_address: str
    notes: str | None
    expires_at: datetime
    driver: PartyOut
    customer: PartyOut
