import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, require_role
from app.core.database import get_session
from app.models.user import Role
from app.schemas.forms import FieldIn, FieldOut, FieldPatch, FormRole, OrderIn
from app.services import form_service as svc

router = APIRouter(prefix="/forms", tags=["forms"], dependencies=[Depends(get_current_user)])
admin_router = APIRouter(prefix="/admin/forms", tags=["admin"], dependencies=[Depends(require_role(Role.ADMIN))])


def _form_out(form: dict) -> dict:
    return {"version": form["version"], "fields": [FieldOut.model_validate(f) for f in form["fields"]]}


def _translate(exc: Exception) -> HTTPException:
    if isinstance(exc, svc.NotFound):
        return HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    if isinstance(exc, svc.DuplicateKey):
        return HTTPException(status.HTTP_409_CONFLICT, "A field with this key already exists")
    if isinstance(exc, svc.CoreField):
        return HTTPException(status.HTTP_409_CONFLICT, "This is a core field: only its label, help text and position can change")
    if isinstance(exc, svc.InvalidOrder):
        return HTTPException(422, "Send every field id of this form exactly once")
    if isinstance(exc, svc.Invalid):
        return HTTPException(422, exc.message)
    raise exc


@router.get("/{role}")
async def read_form(role: FormRole, session: AsyncSession = Depends(get_session)):
    return _form_out(await svc.get_form(session, role))


@admin_router.get("/{role}")
async def admin_read_form(role: FormRole, session: AsyncSession = Depends(get_session)):
    return _form_out(await svc.get_form(session, role, include_inactive=True))


@admin_router.post("/{role}/fields", response_model=FieldOut, status_code=status.HTTP_201_CREATED)
async def add_field(role: FormRole, body: FieldIn, session: AsyncSession = Depends(get_session)):
    try:
        return await svc.add_field(session, role, body)
    except (svc.DuplicateKey, svc.Invalid) as exc:
        raise _translate(exc) from None


@admin_router.patch("/{role}/fields/{field_id}", response_model=FieldOut)
async def update_field(role: FormRole, field_id: uuid.UUID, body: FieldPatch, session: AsyncSession = Depends(get_session)):
    try:
        return await svc.update_field(session, role, field_id, body)
    except (svc.NotFound, svc.CoreField, svc.Invalid) as exc:
        raise _translate(exc) from None


@admin_router.delete("/{role}/fields/{field_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_field(role: FormRole, field_id: uuid.UUID, session: AsyncSession = Depends(get_session)):
    try:
        await svc.deactivate_field(session, role, field_id)
    except (svc.NotFound, svc.CoreField) as exc:
        raise _translate(exc) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@admin_router.put("/{role}/order", status_code=status.HTTP_200_OK)
async def reorder(role: FormRole, body: OrderIn, session: AsyncSession = Depends(get_session)):
    try:
        await svc.reorder(session, role, body.ids)
    except svc.InvalidOrder as exc:
        raise _translate(exc) from None
    return _form_out(await svc.get_form(session, role, include_inactive=True))
