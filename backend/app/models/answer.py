import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base
from app.models.document import DocStatus


class DriverAnswer(Base):
    """A driver's answer to one form field, reviewed on its own (like a document)."""

    __tablename__ = "driver_answers"
    __table_args__ = (UniqueConstraint("driver_id", "field_key", name="uq_driver_answer_field"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    driver_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("driver_profiles.id", ondelete="CASCADE"), index=True)
    field_key: Mapped[str] = mapped_column(String(40))
    value: Mapped[str] = mapped_column(String(500))
    status: Mapped[DocStatus] = mapped_column(
        Enum(DocStatus, native_enum=False, length=20, values_callable=lambda e: [m.value for m in e]),
        default=DocStatus.PENDING,
        server_default="PENDING",
    )
    review_note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
