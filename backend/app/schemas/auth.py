import re
import uuid
from decimal import Decimal
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field


_INDIAN_MOBILE = re.compile(r"(?:\+91|91|0)?([6-9][0-9]{9})", re.ASCII)


def normalize_phone(value: str) -> str:
    """Accept an Indian mobile number in common spellings; store one canonical +91XXXXXXXXXX form."""
    cleaned = re.sub(r"[\s\-]", "", value)
    match = _INDIAN_MOBILE.fullmatch(cleaned)
    if match is None:
        raise ValueError("Enter a valid 10-digit Indian mobile number")
    return f"+91{match.group(1)}"


Phone = Annotated[str, AfterValidator(normalize_phone)]
Password = Annotated[str, Field(min_length=8, max_length=128)]


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class LoginRequest(BaseModel):
    phone: Phone
    password: Annotated[str, Field(max_length=128)]


class RefreshRequest(BaseModel):
    refresh_token: str


class CustomerRegister(BaseModel):
    full_name: Annotated[str, Field(min_length=2, max_length=120)]
    phone: Phone
    password: Password
    email: EmailStr | None = None


class DriverRegister(CustomerRegister):
    licence_number: Annotated[str, Field(min_length=3, max_length=50)]
    experience_years: Annotated[int, Field(ge=0, le=60)]
    hourly_rate: Annotated[Decimal, Field(gt=0, max_digits=8, decimal_places=2)]


class CustomerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    phone: str
    email: str | None
    default_address: str | None


class DriverOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    phone: str
    email: str | None
    licence_number: str
    experience_years: int
    hourly_rate: Decimal
    verification_status: str
    availability_status: str
    rating: Decimal
