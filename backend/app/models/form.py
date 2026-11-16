import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class FormField(Base):
    """One question (or document upload) on a role's registration form, edited by admins."""

    __tablename__ = "form_fields"
    __table_args__ = (UniqueConstraint("role", "key", name="uq_form_field_role_key"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    role: Mapped[str] = mapped_column(String(20))
    key: Mapped[str] = mapped_column(String(40))
    label: Mapped[str] = mapped_column(String(120))
    field_type: Mapped[str] = mapped_column(String(20))
    required: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    help_text: Mapped[str | None] = mapped_column(String(300), nullable=True)
    choices: Mapped[list[str] | None] = mapped_column(JSONB, nullable=True)
    position: Mapped[int] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    is_core: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class FormVersion(Base):
    """Bumped on every change to a role's form so apps can tell when theirs is out of date."""

    __tablename__ = "form_versions"

    role: Mapped[str] = mapped_column(String(20), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
