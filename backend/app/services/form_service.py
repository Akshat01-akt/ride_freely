import re
import uuid
from datetime import date
from decimal import Decimal, InvalidOperation

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.form import FormField, FormVersion
from app.schemas.forms import FieldIn, FieldPatch, _check_choices

MAX_ACTIVE_FIELDS = 30
MAX_TEXT = 500
MAX_NUMBER = Decimal("99999999.99")
MAX_RATE = Decimal("99999.99")  # keeps rate x hours inside the price column
_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


# What migration 0006 seeds. A test keeps the two in step; tests also use it to reset the forms.
DEFAULT_FIELDS = [
    {"role": "driver", "key": "licence_number", "label": "Driving licence number", "field_type": "text", "required": True, "help_text": None, "position": 1, "is_core": True},
    {"role": "driver", "key": "experience_years", "label": "Years of driving experience", "field_type": "number", "required": True, "help_text": None, "position": 2, "is_core": True},
    {"role": "driver", "key": "hourly_rate", "label": "Your hourly rate (INR)", "field_type": "number", "required": True, "help_text": "What you charge per hour of driving", "position": 3, "is_core": True},
    {"role": "driver", "key": "LICENCE", "label": "Driving licence", "field_type": "document", "required": True, "help_text": "A clear photo or PDF of your licence", "position": 4, "is_core": True},
    {"role": "driver", "key": "ID_PROOF", "label": "ID proof", "field_type": "document", "required": True, "help_text": "Aadhaar, voter ID or passport", "position": 5, "is_core": True},
    {"role": "driver", "key": "PHOTO", "label": "Your photo", "field_type": "document", "required": False, "help_text": "A recent passport-style photo", "position": 6, "is_core": True},
    {"role": "customer", "key": "default_address", "label": "Home address", "field_type": "text", "required": False, "help_text": "Used to prefill your pickup location", "position": 1, "is_core": False},
]


class NotFound(Exception):
    pass


class DuplicateKey(Exception):
    pass


class CoreField(Exception):
    """Core fields feed pricing and search, so their meaning cannot be changed."""


class InvalidOrder(Exception):
    pass


class Invalid(Exception):
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


async def _bump(session: AsyncSession, role: str) -> None:
    await session.execute(update(FormVersion).where(FormVersion.role == role).values(version=FormVersion.version + 1))


async def get_form(session: AsyncSession, role: str, include_inactive: bool = False) -> dict:
    query = select(FormField).where(FormField.role == role).order_by(FormField.position, FormField.created_at)
    if not include_inactive:
        query = query.where(FormField.is_active)
    version = await session.scalar(select(FormVersion.version).where(FormVersion.role == role))
    return {"version": version or 1, "fields": list(await session.scalars(query))}


async def _field(session: AsyncSession, role: str, field_id: uuid.UUID) -> FormField:
    field = await session.get(FormField, field_id)
    if field is None or field.role != role:
        raise NotFound
    return field


async def _check_capacity(session: AsyncSession, role: str) -> None:
    active = await session.scalar(select(func.count()).select_from(FormField).where(FormField.role == role, FormField.is_active))
    if active >= MAX_ACTIVE_FIELDS:
        raise Invalid(f"A form can have at most {MAX_ACTIVE_FIELDS} fields")


async def add_field(session: AsyncSession, role: str, data: FieldIn) -> FormField:
    if data.field_type == "document" and role != "driver":
        raise Invalid("Only the driver form can ask for documents")
    await _check_capacity(session, role)
    position = (await session.scalar(select(func.coalesce(func.max(FormField.position), 0)).where(FormField.role == role))) + 1
    field = FormField(role=role, position=position, **data.model_dump())
    session.add(field)
    try:
        await session.flush()
    except IntegrityError:
        await session.rollback()
        raise DuplicateKey from None
    await _bump(session, role)
    await session.commit()
    return field


async def update_field(session: AsyncSession, role: str, field_id: uuid.UUID, patch: FieldPatch) -> FormField:
    field = await _field(session, role, field_id)
    changes = patch.model_dump(exclude_unset=True)
    if field.is_core and (
        changes.get("is_active") is False
        or ("field_type" in changes and changes["field_type"] != field.field_type)
        or (changes.get("required") is False and field.required)
    ):
        raise CoreField
    field_type = changes.get("field_type", field.field_type)
    if field_type == "document" and role != "driver":
        raise Invalid("Only the driver form can ask for documents")
    if "field_type" in changes and "choices" not in changes and field_type != "choice":
        changes["choices"] = None
    try:
        _check_choices(field_type, changes.get("choices", field.choices))
    except ValueError as exc:
        raise Invalid(str(exc)) from None
    if changes.get("is_active") and not field.is_active:
        await _check_capacity(session, role)
    for name, value in changes.items():
        setattr(field, name, value)
    await _bump(session, role)
    await session.commit()
    return field


async def deactivate_field(session: AsyncSession, role: str, field_id: uuid.UUID) -> None:
    field = await _field(session, role, field_id)
    if field.is_core:
        raise CoreField
    field.is_active = False
    await _bump(session, role)
    await session.commit()


async def reorder(session: AsyncSession, role: str, ids: list[uuid.UUID]) -> None:
    existing = set(await session.scalars(select(FormField.id).where(FormField.role == role)))
    if len(ids) != len(set(ids)) or set(ids) != existing:
        raise InvalidOrder
    for position, field_id in enumerate(ids, start=1):
        await session.execute(update(FormField).where(FormField.id == field_id).values(position=position))
    await _bump(session, role)
    await session.commit()


def clean_value(field: FormField, raw: str) -> str:
    """Return the value to store, or raise ValueError with the reason."""
    value = raw.strip() if isinstance(raw, str) else ""
    if field.field_type == "document":
        raise ValueError("Upload this as a document, not as text")
    if not value:
        raise ValueError("This cannot be empty")
    if len(value) > MAX_TEXT:
        raise ValueError(f"Keep this under {MAX_TEXT} characters")
    if field.field_type == "number":
        try:
            number = Decimal(value)
        except InvalidOperation:
            raise ValueError("Enter a number") from None
        if not number.is_finite() or number < 0 or number > MAX_NUMBER:
            raise ValueError("Enter a number between 0 and 99999999.99")
        if field.key == "experience_years" and (number != number.to_integral_value() or number > 60):
            raise ValueError("Enter whole years, 0 to 60")
        if field.key == "hourly_rate" and (number <= 0 or number > MAX_RATE or number != round(number, 2)):
            raise ValueError("Enter a rate above 0 up to 99999.99, with at most 2 decimals")
    elif field.key == "licence_number" and not 3 <= len(value) <= 50:
        raise ValueError("A licence number is 3 to 50 characters")
    elif field.field_type == "date":
        try:
            if not _DATE.match(value):
                raise ValueError
            date.fromisoformat(value)
        except ValueError:
            raise ValueError("Enter a real date as YYYY-MM-DD") from None
    elif field.field_type == "choice" and value not in (field.choices or []):
        raise ValueError("Pick one of the listed options")
    return value
