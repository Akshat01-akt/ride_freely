import uuid
from decimal import Decimal

from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.answer import DriverAnswer
from app.models.document import DocStatus, DriverDocument
from app.models.driver import DriverProfile, VerificationStatus
from app.models.form import FormField
from app.services import form_service
from app.services.review_service import HasActiveBooking, _has_live_booking as has_live_booking, send_back_for_review

class ApplicationInvalid(Exception):
    """Per-field problems, keyed by field key, in words the driver can act on."""

    def __init__(self, errors: dict[str, str]):
        super().__init__(errors)
        self.errors = errors


async def _stored(session: AsyncSession, driver_id: uuid.UUID) -> tuple[dict[str, DriverAnswer], dict[str, DriverDocument]]:
    answers = {a.field_key: a for a in await session.scalars(select(DriverAnswer).where(DriverAnswer.driver_id == driver_id))}
    docs = {d.doc_type: d for d in await session.scalars(select(DriverDocument).where(DriverDocument.driver_id == driver_id))}
    return answers, docs


def _missing_required(fields: list[FormField], answers: dict, docs: dict) -> list[str]:
    return [
        f.key
        for f in fields
        if f.required and (f.key not in docs if f.field_type == "document" else f.key not in answers)
    ]


async def needs_update(session: AsyncSession, profile: DriverProfile) -> list[str]:
    """Required items the driver has not given yet (e.g. a field the admin added later). Informational only."""
    fields = (await form_service.get_form(session, "driver"))["fields"]
    answers, docs = await _stored(session, profile.id)
    return _missing_required(fields, answers, docs)


async def submit(session: AsyncSession, redis: Redis, profile: DriverProfile, submitted: dict[str, str]) -> DriverProfile:
    fields = (await form_service.get_form(session, "driver"))["fields"]
    by_key = {f.key: f for f in fields}
    answers, docs = await _stored(session, profile.id)
    errors: dict[str, str] = {}

    clean: dict[str, str] = {}
    for key, raw in submitted.items():
        if key not in by_key:
            errors[key] = "This is not a field on the form"
            continue
        try:
            clean[key] = form_service.clean_value(by_key[key], raw)
        except ValueError as exc:
            errors[key] = str(exc)

    merged = {k: a.value for k, a in answers.items() if k in by_key} | clean
    for key in _missing_required(fields, {k: 1 for k in merged}, docs):
        errors.setdefault(key, "Upload this document" if by_key[key].field_type == "document" else "This is required")
    for field in fields:
        if field.field_type == "document":
            rejected = docs.get(field.key) is not None and docs[field.key].status == DocStatus.REJECTED
            note = docs[field.key].review_note if rejected else None
        else:
            rejected = field.key in answers and answers[field.key].status == DocStatus.REJECTED and field.key not in clean
            note = answers[field.key].review_note if rejected else None
        if rejected:
            errors.setdefault(field.key, "Fix this item first" + (f": {note}" if note else ""))
    if errors:
        raise ApplicationInvalid(errors)

    # Only changing something an admin may have approved needs a new look. Answering a question for the first time
    # (for example one added later) does not: the driver stays bookable and the answer waits for review.
    changed = False
    for key, value in clean.items():
        existing = answers.get(key)
        if existing is None:
            session.add(DriverAnswer(driver_id=profile.id, field_key=key, value=value))
        elif existing.value != value or existing.status == DocStatus.REJECTED:
            changed = True
    if changed and profile.verification_status == VerificationStatus.APPROVED and await has_live_booking(session, profile.id):
        raise HasActiveBooking
    for key, value in clean.items():
        existing = answers.get(key)
        if existing is not None and (existing.value != value or existing.status == DocStatus.REJECTED):
            existing.value, existing.status, existing.review_note = value, DocStatus.PENDING, None
    profile.licence_number = merged["licence_number"]
    profile.experience_years = int(Decimal(merged["experience_years"]))
    profile.hourly_rate = Decimal(merged["hourly_rate"])

    if profile.verification_status in (VerificationStatus.NOT_SUBMITTED, VerificationStatus.REJECTED):
        profile.verification_status = VerificationStatus.PENDING
    elif profile.verification_status == VerificationStatus.APPROVED and changed:
        await send_back_for_review(session, redis, profile)
    await session.commit()
    return profile


async def view(session: AsyncSession, profile: DriverProfile) -> dict:
    answers, docs = await _stored(session, profile.id)
    return {
        "status": profile.verification_status,
        "form_version": (await form_service.get_form(session, "driver"))["version"],
        "answers": [
            {"key": a.field_key, "value": a.value, "status": a.status, "review_note": a.review_note}
            for a in sorted(answers.values(), key=lambda a: a.field_key)
        ],
        "documents": [
            {"id": d.id, "doc_type": d.doc_type, "status": d.status, "review_note": d.review_note}
            for d in sorted(docs.values(), key=lambda d: d.doc_type)
        ],
        "needs_update": await needs_update(session, profile),
    }
