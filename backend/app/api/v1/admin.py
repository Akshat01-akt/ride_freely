import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_role
from app.core.database import get_session
from app.core.redis import get_redis
from app.models.booking import Booking, BookingStatus
from app.models.document import DocStatus, DriverDocument
from app.models.driver import DriverProfile, VerificationStatus
from app.models.user import Role, User
from app.schemas.auth import DocumentOut
from app.services import review_service as review
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
        stmt = stmt.where(User.full_name.ilike(pattern, escape="\\") | User.phone.ilike(pattern, escape="\\"))
    return stmt


@router.get("/stats")
async def stats(session: AsyncSession = Depends(get_session)):
    roles = dict((await session.execute(select(User.role, func.count()).group_by(User.role))).all())
    verification = dict(
        (await session.execute(select(DriverProfile.verification_status, func.count()).group_by(DriverProfile.verification_status))).all()
    )
    pending_docs = await session.scalar(select(func.count()).select_from(DriverDocument).where(DriverDocument.status == DocStatus.PENDING))
    return {
        "customers": roles.get(Role.CUSTOMER, 0),
        "admins": roles.get(Role.ADMIN, 0),
        "drivers": {
            "total": roles.get(Role.DRIVER, 0),
            **{v.value: verification.get(v, 0) for v in VerificationStatus},
        },
        "pending_documents": pending_docs,
    }


@router.get("/drivers")
async def list_drivers(
    verification: VerificationStatus | None = None,
    q: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    session: AsyncSession = Depends(get_session),
):
    base = select(DriverProfile, User).join(User, User.id == DriverProfile.user_id)
    if verification is not None:
        base = base.where(DriverProfile.verification_status == verification)
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
    return {
        "id": p.id,
        "user_id": u.id,
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
            {"id": u.id, "full_name": u.full_name, "phone": u.phone, "role": u.role, "is_active": u.is_active, "created_at": u.created_at}
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
