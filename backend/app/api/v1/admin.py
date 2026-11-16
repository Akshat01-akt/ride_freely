import uuid
from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.api.deps import require_role
from app.core.database import get_session
from app.core.redis import get_redis
from app.models.booking import Booking, BookingStatus
from app.models.answer import DriverAnswer
from app.models.customer import CustomerProfile
from app.models.customer_answer import CustomerAnswer
from app.models.document import DocStatus, DriverDocument
from app.models.location import DriverLocation
from app.models.driver import AvailabilityStatus, DriverProfile, VerificationStatus
from app.models.user import Role, User
from app.schemas.auth import DocumentOut
from app.services import application_service, review_service as review
from app.services.admin_queries import needs_update_clause
from app.services.location_service import live_drivers
from app.services.storage import FileStorage, get_storage

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_role(Role.ADMIN))])


class PendingDriver(BaseModel):
    id: uuid.UUID
    full_name: str
    phone: str | None
    licence_number: str | None
    experience_years: int | None
    documents: list[DocumentOut]


class DocumentDecision(BaseModel):
    status: Literal["APPROVED", "REJECTED"]
    note: str | None = Field(default=None, max_length=500)


class VerificationDecision(BaseModel):
    status: Literal["APPROVED", "REJECTED"]
    note: str | None = Field(default=None, max_length=500)


class AnswerDecision(BaseModel):
    status: Literal["APPROVED", "REJECTED"]
    note: str | None = Field(default=None, max_length=500)


class SuspensionRequest(BaseModel):
    suspended: bool


def _not_found() -> HTTPException:
    return HTTPException(status.HTTP_404_NOT_FOUND, "Not found")


@router.get("/drivers/pending", response_model=list[PendingDriver])
async def pending_drivers(session: AsyncSession = Depends(get_session)):
    rows = await session.execute(
        select(DriverProfile, User)
        .join(User, User.id == DriverProfile.user_id)
        .where(DriverProfile.verification_status == VerificationStatus.PENDING)
        .order_by(User.created_at)
    )
    out = []
    for profile, user in rows.all():
        docs = list(await session.scalars(select(DriverDocument).where(DriverDocument.driver_id == profile.id)))
        out.append(
            PendingDriver(
                id=profile.id,
                full_name=user.full_name,
                phone=user.phone,
                licence_number=profile.licence_number,
                experience_years=profile.experience_years,
                documents=[DocumentOut.model_validate(d) for d in docs],
            )
        )
    return out


@router.get("/documents/{doc_id}/file")
async def download_document(doc_id: uuid.UUID, session: AsyncSession = Depends(get_session), storage: FileStorage = Depends(get_storage)):
    doc = await session.get(DriverDocument, doc_id)
    if doc is None:
        raise _not_found()
    data = await storage.read(doc.file_key)
    extension = {"image/png": "png", "image/jpeg": "jpg", "application/pdf": "pdf"}.get(doc.content_type, "bin")
    return Response(
        data,
        media_type=doc.content_type,
        headers={
            "Content-Disposition": f'attachment; filename="document.{extension}"',
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "sandbox; default-src 'none'",
            "Cache-Control": "private, no-store",
        },
    )


@router.patch("/documents/{doc_id}", response_model=DocumentOut)
async def decide_document(
    doc_id: uuid.UUID,
    body: DocumentDecision,
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    try:
        return await review.review_document(session, redis, doc_id, DocStatus(body.status), body.note)
    except review.NotFound:
        raise _not_found() from None


@router.patch("/drivers/{driver_id}/answers/{key}")
async def decide_answer(
    driver_id: uuid.UUID,
    key: str,
    body: AnswerDecision,
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    try:
        answer = await review.review_answer(session, redis, driver_id, key, DocStatus(body.status), body.note)
    except review.NotFound:
        raise _not_found() from None
    return {"key": answer.field_key, "status": answer.status, "review_note": answer.review_note}


@router.patch("/drivers/{driver_id}/verification")
async def decide_driver(
    driver_id: uuid.UUID,
    body: VerificationDecision,
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    try:
        profile = await review.set_verification(session, redis, driver_id, VerificationStatus(body.status))
    except review.NotFound:
        raise _not_found() from None
    except review.RequirementsNotMet:
        raise HTTPException(status.HTTP_409_CONFLICT, "Approve the driver's licence and ID proof first") from None
    except review.HasActiveBooking:
        raise HTTPException(status.HTTP_409_CONFLICT, "This driver has an active booking. Change their status after it ends.") from None
    return {"id": profile.id, "verification_status": profile.verification_status, "availability_status": profile.availability_status}


@router.patch("/drivers/{driver_id}/suspension")
async def suspend_driver(
    driver_id: uuid.UUID,
    body: SuspensionRequest,
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    try:
        profile = await review.set_suspension(session, redis, driver_id, body.suspended)
    except review.NotFound:
        raise _not_found() from None
    except review.HasActiveBooking:
        raise HTTPException(status.HTTP_409_CONFLICT, "This driver has an active booking. Suspend after it ends.") from None
    return {"id": profile.id, "availability_status": profile.availability_status}


# ---------------------------------------------------------------- website: dashboard, listings, accounts

class ActiveRequest(BaseModel):
    active: bool


def _like(text: str) -> str:
    """Text to match literally inside ILIKE: % and _ are escaped so they are not wildcards."""
    text = text.strip()[:100]
    return "%" + text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _search(stmt, q: str | None):
    if q and q.strip():
        pattern = _like(q)
        stmt = stmt.where(
            User.full_name.ilike(pattern, escape="\\") | User.phone.ilike(pattern, escape="\\") | User.email.ilike(pattern, escape="\\")
        )
    return stmt


@router.get("/stats")
async def stats(session: AsyncSession = Depends(get_session)):
    roles = dict((await session.execute(select(User.role, func.count()).group_by(User.role))).all())
    verification = dict(
        (await session.execute(select(DriverProfile.verification_status, func.count()).group_by(DriverProfile.verification_status))).all()
    )
    pending_docs = await session.scalar(select(func.count()).select_from(DriverDocument).where(DriverDocument.status == DocStatus.PENDING))
    needs_update = await session.scalar(
        select(func.count()).select_from(DriverProfile).where(DriverProfile.verification_status == VerificationStatus.APPROVED, needs_update_clause())
    )
    online_now = await session.scalar(
        select(func.count()).select_from(DriverLocation).join(DriverProfile, DriverProfile.id == DriverLocation.driver_id).where(
            DriverProfile.availability_status.in_([AvailabilityStatus.AVAILABLE, AvailabilityStatus.RESERVED, AvailabilityStatus.BOOKED, AvailabilityStatus.ON_TRIP]),
            DriverLocation.recorded_at > func.now() - text("interval '30 seconds'"),
        )
    )
    today = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
    bookings_today = await session.scalar(select(func.count()).select_from(Booking).where(Booking.created_at >= today))
    return {
        "customers": roles.get(Role.CUSTOMER, 0),
        "admins": roles.get(Role.ADMIN, 0),
        "drivers": {
            "total": roles.get(Role.DRIVER, 0),
            **{v.value: verification.get(v, 0) for v in VerificationStatus},
        },
        "pending_documents": pending_docs,
        "not_submitted": verification.get(VerificationStatus.NOT_SUBMITTED, 0),
        "rejected": verification.get(VerificationStatus.REJECTED, 0),
        "needs_update": needs_update,
        "online_now": online_now,
        "bookings_today": bookings_today,
    }


@router.get("/drivers")
async def list_drivers(
    verification: VerificationStatus | None = None,
    availability: AvailabilityStatus | None = None,
    needs_update: bool = False,
    q: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    session: AsyncSession = Depends(get_session),
):
    base = select(DriverProfile, User).join(User, User.id == DriverProfile.user_id)
    if verification is not None:
        base = base.where(DriverProfile.verification_status == verification)
    if availability is not None:
        base = base.where(DriverProfile.availability_status == availability)
    if needs_update:
        base = base.where(needs_update_clause())
    base = _search(base, q)
    total = await session.scalar(select(func.count()).select_from(base.subquery()))
    rows = (await session.execute(base.order_by(User.created_at.desc(), User.id).limit(limit).offset(offset))).all()
    return {
        "total": total,
        "items": [
            {
                "id": p.id,
                "full_name": u.full_name,
                "phone": u.phone,
                "email": u.email,
                "verification_status": p.verification_status,
                "availability_status": p.availability_status,
                "rating": str(p.rating),
                "hourly_rate": str(p.hourly_rate),
                "is_active": u.is_active,
                "created_at": u.created_at,
            }
            for p, u in rows
        ],
    }


@router.get("/drivers/live")
async def live_map(session: AsyncSession = Depends(get_session), redis: Redis = Depends(get_redis)):
    return {"drivers": await live_drivers(session, redis)}


@router.get("/drivers/{driver_id}")
async def driver_detail(driver_id: uuid.UUID, session: AsyncSession = Depends(get_session)):
    row = (
        await session.execute(
            select(DriverProfile, User).join(User, User.id == DriverProfile.user_id).where(DriverProfile.id == driver_id)
        )
    ).first()
    if row is None:
        raise _not_found()
    p, u = row
    docs = list(await session.scalars(select(DriverDocument).where(DriverDocument.driver_id == p.id).order_by(DriverDocument.doc_type)))
    trips = await session.scalar(
        select(func.count()).select_from(Booking).where(Booking.driver_id == p.id, Booking.status == BookingStatus.COMPLETED)
    )
    answers = list(await session.scalars(select(DriverAnswer).where(DriverAnswer.driver_id == p.id).order_by(DriverAnswer.field_key)))
    last_seen = await session.scalar(select(DriverLocation.recorded_at).where(DriverLocation.driver_id == p.id))
    return {
        "id": p.id,
        "user_id": u.id,
        "answers": [{"key": a.field_key, "value": a.value, "status": a.status, "review_note": a.review_note} for a in answers],
        "needs_update": await application_service.needs_update(session, p),
        "last_seen": last_seen,
        "full_name": u.full_name,
        "phone": u.phone,
        "email": u.email,
        "licence_number": p.licence_number,
        "experience_years": p.experience_years,
        "hourly_rate": str(p.hourly_rate),
        "rating": str(p.rating),
        "verification_status": p.verification_status,
        "availability_status": p.availability_status,
        "is_active": u.is_active,
        "created_at": u.created_at,
        "completed_trips": trips,
        "documents": [
            {
                "id": d.id,
                "doc_type": d.doc_type,
                "status": d.status,
                "review_note": d.review_note,
                "content_type": d.content_type,
                "size_bytes": d.size_bytes,
                "updated_at": d.updated_at,
            }
            for d in docs
        ],
    }


@router.get("/users")
async def list_users(
    role: Role | None = None,
    q: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    session: AsyncSession = Depends(get_session),
):
    base = select(User)
    if role is not None:
        base = base.where(User.role == role)
    base = _search(base, q)
    total = await session.scalar(select(func.count()).select_from(base.subquery()))
    users = (await session.scalars(base.order_by(User.created_at.desc(), User.id).limit(limit).offset(offset))).all()
    return {
        "total": total,
        "items": [
            {"id": u.id, "full_name": u.full_name, "phone": u.phone, "email": u.email, "role": u.role, "is_active": u.is_active, "created_at": u.created_at}
            for u in users
        ],
    }


@router.patch("/users/{user_id}/active")
async def set_user_active(
    user_id: uuid.UUID,
    body: ActiveRequest,
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    try:
        user = await review.set_user_active(session, redis, user_id, body.active)
    except review.NotFound:
        raise _not_found() from None
    except review.ProtectedAccount:
        raise HTTPException(status.HTTP_409_CONFLICT, "Admin accounts cannot be deactivated here") from None
    except review.HasActiveBooking:
        raise HTTPException(status.HTTP_409_CONFLICT, "This user has an accepted or running booking. Try again after it ends.") from None
    return {"id": user.id, "is_active": user.is_active}


@router.get("/users/{user_id}")
async def user_detail(user_id: uuid.UUID, session: AsyncSession = Depends(get_session)):
    user = await session.get(User, user_id)
    if user is None:
        raise _not_found()
    driver_id = await session.scalar(select(DriverProfile.id).where(DriverProfile.user_id == user.id))
    customer = await session.scalar(select(CustomerProfile).where(CustomerProfile.user_id == user.id))
    answers = {}
    if customer is not None:
        answers = {a.field_key: a.value for a in await session.scalars(select(CustomerAnswer).where(CustomerAnswer.customer_id == customer.id))}
    return {
        "id": user.id,
        "full_name": user.full_name,
        "phone": user.phone,
        "email": user.email,
        "role": user.role,
        "is_active": user.is_active,
        "created_at": user.created_at,
        "driver_id": driver_id,
        "customer_answers": answers,
    }


def _booking_row(b: Booking, driver_name: str, driver_phone: str | None, customer_name: str, customer_phone: str | None) -> dict:
    return {
        "id": b.id,
        "status": b.status,
        "booking_type": b.booking_type,
        "start_time": b.start_time,
        "end_time": b.end_time,
        "hours": b.hours,
        "price_amount": str(b.price_amount),
        "pickup_address": b.pickup_address,
        "notes": b.notes,
        "rating": b.rating,
        "driver_id": b.driver_id,
        "driver_name": driver_name,
        "driver_phone": driver_phone,
        "customer_id": b.customer_id,
        "customer_name": customer_name,
        "customer_phone": customer_phone,
        "created_at": b.created_at,
        "completed_at": b.completed_at,
    }


def _bookings_query():
    driver_user, customer_user = aliased(User), aliased(User)
    query = (
        select(Booking, driver_user.full_name, driver_user.phone, customer_user.full_name, customer_user.phone)
        .join(DriverProfile, DriverProfile.id == Booking.driver_id)
        .join(driver_user, driver_user.id == DriverProfile.user_id)
        .join(CustomerProfile, CustomerProfile.id == Booking.customer_id)
        .join(customer_user, customer_user.id == CustomerProfile.user_id)
    )
    return query


@router.get("/bookings")
async def list_bookings(
    status_: BookingStatus | None = Query(None, alias="status"),
    driver_id: uuid.UUID | None = None,
    customer_id: uuid.UUID | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    session: AsyncSession = Depends(get_session),
):
    query = _bookings_query()
    for column, value in ((Booking.status, status_), (Booking.driver_id, driver_id), (Booking.customer_id, customer_id)):
        if value is not None:
            query = query.where(column == value)
    total = await session.scalar(select(func.count()).select_from(query.subquery()))
    rows = (await session.execute(query.order_by(Booking.created_at.desc(), Booking.id).limit(limit).offset(offset))).all()
    return {"total": total, "items": [_booking_row(*row) for row in rows]}


@router.get("/bookings/{booking_id}")
async def booking_detail(booking_id: uuid.UUID, session: AsyncSession = Depends(get_session)):
    row = (await session.execute(_bookings_query().where(Booking.id == booking_id))).first()
    if row is None:
        raise _not_found()
    return _booking_row(*row)
