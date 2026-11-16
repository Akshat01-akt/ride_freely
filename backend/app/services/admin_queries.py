from sqlalchemy import and_, exists, or_, select

from app.models.answer import DriverAnswer
from app.models.document import DriverDocument
from app.models.driver import DriverProfile
from app.models.form import FormField


def needs_update_clause():
    """True for drivers missing an answer or document the form now requires (SQL twin of application_service.needs_update)."""
    missing_answer = ~exists().where(DriverAnswer.driver_id == DriverProfile.id, DriverAnswer.field_key == FormField.key)
    missing_doc = ~exists().where(DriverDocument.driver_id == DriverProfile.id, DriverDocument.doc_type == FormField.key)
    return exists(
        select(FormField.id).where(
            FormField.role == "driver",
            FormField.is_active,
            FormField.required,
            or_(and_(FormField.field_type == "document", missing_doc), and_(FormField.field_type != "document", missing_answer)),
        )
    )
