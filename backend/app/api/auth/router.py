"""Auth router — wires HTTP endpoints to AuthService."""

from fastapi import APIRouter, Depends
from fastapi.security import OAuth2PasswordBearer

from app.api.auth.dependencies import get_current_user
from app.api.auth.models import (
    AuthResponse,
    LoginRequest,
    MessageResponse,
    RefreshRequest,
    RegisterRequest,
    UserProfile,
    VerifyEmailRequest,
)
from app.api.auth.service import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])

_bearer = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


@router.post("/register", response_model=AuthResponse)
async def register(body: RegisterRequest) -> AuthResponse:
    """Create a new user account and return tokens."""
    return await auth_service.register(body.email, body.password)


@router.post("/login", response_model=AuthResponse)
async def login(body: LoginRequest) -> AuthResponse:
    """Authenticate with email/password and return tokens."""
    return await auth_service.login(body.email, body.password)


@router.post("/logout", response_model=MessageResponse)
async def logout(token: str = Depends(_bearer)) -> MessageResponse:
    """Invalidate the current session."""
    await auth_service.logout(token)
    return MessageResponse(message="Logged out successfully")


@router.post("/refresh", response_model=AuthResponse)
async def refresh(body: RefreshRequest) -> AuthResponse:
    """Exchange a refresh token for a new token pair."""
    return await auth_service.refresh_token(body.refresh_token)


@router.post("/verify-email", response_model=MessageResponse)
async def verify_email(body: VerifyEmailRequest) -> MessageResponse:
    """Confirm email verification code."""
    await auth_service.verify_email(body.email, body.code)
    return MessageResponse(message="Email verified successfully")


@router.get("/me", response_model=UserProfile)
async def me(current_user: UserProfile = Depends(get_current_user)) -> UserProfile:
    """Return the authenticated user's profile."""
    return current_user
