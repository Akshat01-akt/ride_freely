from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.models.user import Role
from app.schemas.auth import (
    CustomerRegister,
    DriverRegister,
    LoginRequest,
    RefreshRequest,
    TokenPair,
)
from app.services import auth_service as svc

router = APIRouter(prefix="/auth", tags=["auth"])

_BAD_LOGIN = HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email, mobile number or password")
_TAKEN = HTTPException(status.HTTP_409_CONFLICT, "Email or mobile number is already registered")


@router.post("/customer/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
async def register_customer(data: CustomerRegister, session: AsyncSession = Depends(get_session)):
    try:
        user = await svc.register_customer(session, data)
    except svc.IdentifierTaken:
        raise _TAKEN from None
    return svc.issue_tokens(user)


@router.post("/driver/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
async def register_driver(data: DriverRegister, session: AsyncSession = Depends(get_session)):
    try:
        user = await svc.register_driver(session, data)
    except svc.IdentifierTaken:
        raise _TAKEN from None
    return svc.issue_tokens(user)


async def _login(data: LoginRequest, session: AsyncSession, role: Role) -> TokenPair:
    try:
        user = await svc.authenticate(session, data.identifier, data.password, role)
    except svc.InvalidCredentials:
        raise _BAD_LOGIN from None
    return svc.issue_tokens(user)


@router.post("/customer/login", response_model=TokenPair)
async def login_customer(data: LoginRequest, session: AsyncSession = Depends(get_session)):
    return await _login(data, session, Role.CUSTOMER)


@router.post("/driver/login", response_model=TokenPair)
async def login_driver(data: LoginRequest, session: AsyncSession = Depends(get_session)):
    return await _login(data, session, Role.DRIVER)


@router.post("/admin/login", response_model=TokenPair)
async def login_admin(data: LoginRequest, session: AsyncSession = Depends(get_session)):
    return await _login(data, session, Role.ADMIN)


@router.post("/refresh", response_model=TokenPair)
async def refresh(data: RefreshRequest, session: AsyncSession = Depends(get_session)):
    try:
        return await svc.refresh(session, data.refresh_token)
    except svc.InvalidCredentials:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token") from None
