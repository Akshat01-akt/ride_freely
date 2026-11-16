from redis.asyncio import Redis
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_driver_profile, require_role
from app.core.database import get_session
from app.models.document import DriverDocument
from app.models.driver import AvailabilityStatus, DriverProfile
from app.models.user import Role, User
from app.services.location_service import nearby_drivers
from app.schemas.auth import ApplicationIn, AvailabilityRequest, DocumentOut, DriverOut
from app.core.redis import get_redis
from app.services import application_service, document_service as docs, form_service
from app.services import review_service
from app.services.earnings_service import driver_earnings
from app.services.storage import FileStorage, get_storage

router = APIRouter(prefix="/drivers", tags=["drivers"])


@router.get("/me", response_model=DriverOut)
async def me(user: User = Depends(require_role(Role.DRIVER)), session: AsyncSession = Depends(get_session)):
    profile = await session.scalar(select(DriverProfile).where(DriverProfile.user_id == user.id))
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Driver profile not found")
    return DriverOut(
        id=user.id,
        full_name=user.full_name,
        phone=user.phone,
        email=user.email,
        licence_number=profile.licence_number,
        experience_years=profile.experience_years,
        hourly_rate=profile.hourly_rate,
        verification_status=profile.verification_status,
        availability_status=profile.availability_status,
        rating=profile.rating,
        application=await application_service.view(session, profile),
    )


@router.post("/application", response_model=DriverOut)
async def submit_application(
    body: ApplicationIn,
    profile: DriverProfile = Depends(get_driver_profile),
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
    user: User = Depends(require_role(Role.DRIVER)),
):
    try:
        await application_service.submit(session, redis, profile, body.answers)
    except application_service.ApplicationInvalid as exc:
        raise HTTPException(
            422, [{"loc": ["answers", key], "msg": msg, "type": "value_error"} for key, msg in exc.errors.items()]
        ) from None
    return await me(user, session)


@router.get("/earnings")
async def earnings(profile: DriverProfile = Depends(get_driver_profile), session: AsyncSession = Depends(get_session)):
    return await driver_earnings(session, profile.id)


@router.post("/documents", response_model=DocumentOut, status_code=status.HTTP_201_CREATED)
async def upload_document(
    doc_type: str = Form(..., max_length=40),
    file: UploadFile = File(...),
    profile: DriverProfile = Depends(get_driver_profile),
    session: AsyncSession = Depends(get_session),
    storage: FileStorage = Depends(get_storage),
    redis: Redis = Depends(get_redis),
):
    form = await form_service.get_form(session, "driver")
    if doc_type not in {f.key for f in form["fields"] if f.field_type == "document"}:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "This is not a document on the application form")
    data = await file.read(docs.MAX_BYTES + 1)
    try:
        content_type = docs.validate_upload(file.content_type, data)
    except docs.FileTooLarge:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "File is larger than 5 MB") from None
    except docs.UnsupportedFile:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Upload a JPEG, PNG or PDF file") from None
    try:
        return await docs.save_document(session, storage, redis, profile, doc_type, content_type, data)
    except docs.UploadConflict:
        raise HTTPException(status.HTTP_409_CONFLICT, "Another upload for this document is in progress. Try again.") from None


@router.get("/documents", response_model=list[DocumentOut])
async def list_documents(profile: DriverProfile = Depends(get_driver_profile), session: AsyncSession = Depends(get_session)):
    rows = await session.scalars(select(DriverDocument).where(DriverDocument.driver_id == profile.id).order_by(DriverDocument.doc_type))
    return list(rows)


@router.patch("/availability")
async def set_availability(
    body: AvailabilityRequest,
    profile: DriverProfile = Depends(get_driver_profile),
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    try:
        profile = await review_service.set_availability(session, redis, profile, AvailabilityStatus(body.status))
    except review_service.NotApproved:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Your documents must be approved before you can go online") from None
    except review_service.StateLocked:
        raise HTTPException(status.HTTP_409_CONFLICT, "You cannot change your availability right now") from None
    return {"availability_status": profile.availability_status, "verification_status": profile.verification_status}


@router.get("/nearby")
async def nearby(
    latitude: float = Query(ge=-90, le=90, allow_inf_nan=False),
    longitude: float = Query(ge=-180, le=180, allow_inf_nan=False),
    radius: float = Query(default=5000, gt=0, le=20000, allow_inf_nan=False),
    _: User = Depends(require_role(Role.CUSTOMER)),
    session: AsyncSession = Depends(get_session),
    redis: Redis = Depends(get_redis),
):
    return {"drivers": await nearby_drivers(session, redis, latitude, longitude, radius)}
