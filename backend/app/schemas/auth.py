import re
import uuid
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field, model_validator


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
    """`identifier` is an email address or a mobile number; the old `phone` key is still accepted."""

    identifier: Annotated[str, Field(min_length=1, max_length=254)]
    password: Annotated[str, Field(max_length=128)]

    @model_validator(mode="before")
    @classmethod
    def _legacy_phone_key(cls, data):
        if isinstance(data, dict) and "identifier" not in data and "phone" in data:
            data = {**data, "identifier": data["phone"]}
        return data


class RefreshRequest(BaseModel):
    refresh_token: str


class CustomerRegister(BaseModel):
    """Sign-up: a name, an email or a mobile number (or both) and a password. Nothing else."""

    full_name: Annotated[str, Field(min_length=2, max_length=120)]
    phone: Phone | None = None
    email: EmailStr | None = None
    password: Password

    @model_validator(mode="after")
    def _needs_an_identifier(self):
        if self.phone is None and self.email is None:
            raise ValueError("Enter an email address or a mobile number")
        return self


class DriverRegister(CustomerRegister):
    # Transitional: removed in Task 3 when the application form takes over.
    licence_number: Annotated[str | None, Field(min_length=3, max_length=50)] = None
    experience_years: Annotated[int | None, Field(ge=0, le=60)] = None
    hourly_rate: Annotated[Decimal | None, Field(gt=0, max_digits=8, decimal_places=2)] = None


class CustomerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    phone: str | None
    email: str | None
    default_address: str | None


class DriverOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    phone: str | None
    email: str | None
    licence_number: str | None
    experience_years: int | None
    hourly_rate: Decimal | None
    verification_status: str
    availability_status: str
    rating: Decimal


class DocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    doc_type: str
    status: str
    review_note: str | None = None


class AvailabilityRequest(BaseModel):
    status: Literal["AVAILABLE", "OFFLINE"]


_Finite = {"allow_inf_nan": False}


class LocationUpdate(BaseModel):
    latitude: Annotated[float, Field(ge=-90, le=90, **_Finite)]
    longitude: Annotated[float, Field(ge=-180, le=180, **_Finite)]
    heading: Annotated[float | None, Field(ge=0, le=360, **_Finite)] = None
    speed: Annotated[float | None, Field(ge=0, **_Finite)] = None
    accuracy: Annotated[float | None, Field(ge=0, **_Finite)] = None
