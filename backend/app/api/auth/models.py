"""Pydantic models for authentication request/response validation."""

from pydantic import BaseModel


# --- Request Models ---

class RegisterRequest(BaseModel):
    email: str
    password: str


class LoginRequest(BaseModel):
    email: str
    password: str


class VerifyEmailRequest(BaseModel):
    email: str
    code: str


class RefreshRequest(BaseModel):
    refresh_token: str


# --- Response Models ---

class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds


class UserProfile(BaseModel):
    user_id: str
    email: str
    created_at: str
    scan_count: int = 0
    subscription_tier: str = "free"


class MessageResponse(BaseModel):
    message: str
