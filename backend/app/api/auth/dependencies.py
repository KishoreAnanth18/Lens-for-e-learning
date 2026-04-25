"""FastAPI dependency for extracting and validating the current user."""

from fastapi import Depends
from fastapi.security import OAuth2PasswordBearer

from app.api.auth.models import UserProfile
from app.api.auth.service import auth_service

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


async def get_current_user(
    token: str = Depends(oauth2_scheme),
) -> UserProfile:
    """Validate the bearer token and return the authenticated user profile."""
    return await auth_service.get_current_user(token)
