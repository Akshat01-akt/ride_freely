from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.customer import CustomerProfile
from app.models.customer_answer import CustomerAnswer
from app.services import form_service
from app.services.application_service import ApplicationInvalid


async def answers_of(session: AsyncSession, profile: CustomerProfile) -> dict[str, str]:
    rows = await session.scalars(select(CustomerAnswer).where(CustomerAnswer.customer_id == profile.id))
    return {a.field_key: a.value for a in rows}


async def view(session: AsyncSession, profile: CustomerProfile) -> dict:
    form = await form_service.get_form(session, "customer")
    answers = await answers_of(session, profile)
    return {
        "answers": answers,
        "needs_update": [f.key for f in form["fields"] if f.required and f.key not in answers],
        "form_version": form["version"],
    }


async def save(session: AsyncSession, profile: CustomerProfile, submitted: dict[str, str]) -> None:
    """Optional, non-blocking: store the given answers (the rest stay as they were)."""
    by_key = {f.key: f for f in (await form_service.get_form(session, "customer"))["fields"]}
    errors, clean = {}, {}
    for key, raw in submitted.items():
        if key not in by_key:
            errors[key] = "This is not a field on the form"
            continue
        try:
            clean[key] = form_service.clean_value(by_key[key], raw)
        except ValueError as exc:
            errors[key] = str(exc)
    if errors:
        raise ApplicationInvalid(errors)
    stored = {a.field_key: a for a in await session.scalars(select(CustomerAnswer).where(CustomerAnswer.customer_id == profile.id))}
    for key, value in clean.items():
        if key in stored:
            stored[key].value = value
        else:
            session.add(CustomerAnswer(customer_id=profile.id, field_key=key, value=value))
    if "default_address" in clean:
        profile.default_address = clean["default_address"]
    await session.commit()
