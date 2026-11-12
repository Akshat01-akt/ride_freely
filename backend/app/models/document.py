import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class DocType(StrEnum):
    LICENCE = "LICENCE"
    ID_PROOF = "ID_PROOF"
    PHOTO = "PHOTO"


class DocStatus(StrEnum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


def _enum(cls: type[StrEnum]) -> Enum:
    return Enum(cls, native_enum=False, length=20, values_callable=lambda e: [m.value for m in e])


class DriverDocument(Base):
    __tablename__ = "driver_documents"
    __table_args__ = (UniqueConstraint("driver_id", "doc_type", name="uq_driver_doc_type"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    driver_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("driver_profiles.id", ondelete="CASCADE"), index=True)
    doc_type: Mapped[DocType] = mapped_column(_enum(DocType))
    file_key: Mapped[str] = mapped_column(String(200))
    content_type: Mapped[str] = mapped_column(String(100))
    size_bytes: Mapped[int] = mapped_column(Integer)
    status: Mapped[DocStatus] = mapped_column(_enum(DocStatus), default=DocStatus.PENDING, server_default="PENDING")
    review_note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
