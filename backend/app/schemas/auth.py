import re
import uuid
from decimal import Decimal
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field


def normalize_phone(value: str) -> str:
    cleaned = re.sub(r"[\s\-]", "", value)
    if re.fullmatch(r"\+\d{10,15}", cleaned):
        return cleaned
    if re.fullmatch(r"\d{10}", cleaned):
        return f"+91{cleaned}"
    if re.fullmatch(r"91\d{10}", cleaned):
        return f"+{cleaned}"
    raise ValueError("Enter a valid phone number")


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
