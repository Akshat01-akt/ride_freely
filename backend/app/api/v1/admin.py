import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_role
from app.core.database import get_session
from app.core.redis import get_redis
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
    phone: str
    licence_number: str
    experience_years: int
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
