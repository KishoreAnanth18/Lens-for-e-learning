"""Authentication service — supports mock mode and Cognito mode."""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException, status
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.api.auth.models import AuthResponse, UserProfile
from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# In-memory store for mock mode: {email: {password_hash, user_id, created_at, ...}}
_mock_users: dict = {}
# Revoked tokens in mock mode (logout)
_revoked_tokens: set = set()


def _make_tokens(user_id: str, email: str) -> AuthResponse:
    """Create access + refresh JWT pair."""
    expire_seconds = settings.TOKEN_EXPIRE_DAYS * 24 * 3600
    now = datetime.now(timezone.utc)
    access_payload = {
        "sub": user_id,
        "email": email,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(seconds=expire_seconds),
    }
    refresh_payload = {
        "sub": user_id,
        "email": email,
        "type": "refresh",
        "iat": now,
        "exp": now + timedelta(seconds=expire_seconds),
    }
    access_token = jwt.encode(
        access_payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM
    )
    refresh_token = jwt.encode(
        refresh_payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM
    )
    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=expire_seconds,
        user_id=user_id,
        email=email,
    )


class AuthService:
    """Handles authentication in mock or Cognito mode."""

    # ------------------------------------------------------------------ #
    #  Mock helpers                                                        #
    # ------------------------------------------------------------------ #

    def _mock_register(self, email: str, password: str) -> AuthResponse:
        if email in _mock_users:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered",
            )
        user_id = str(uuid.uuid4())
        _mock_users[email] = {
            "user_id": user_id,
            "email": email,
            "password_hash": pwd_context.hash(password),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "scan_count": 0,
            "subscription_tier": "free",
        }
        return _make_tokens(user_id, email)

    def _mock_login(self, email: str, password: str) -> AuthResponse:
        user = _mock_users.get(email)
        if not user or not pwd_context.verify(password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials",
            )
        return _make_tokens(user["user_id"], email)

    def _mock_logout(self, access_token: str) -> None:
        _revoked_tokens.add(access_token)

    def _mock_refresh(self, refresh_token: str) -> AuthResponse:
        try:
            payload = jwt.decode(
                refresh_token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM],
            )
        except JWTError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired refresh token",
            )
        if payload.get("type") != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Not a refresh token",
            )
        return _make_tokens(payload["sub"], payload["email"])

    def _mock_verify_email(self, email: str, code: str) -> None:
        # In mock mode verification is a no-op (always succeeds)
        if email not in _mock_users:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User not found",
            )

    def _mock_get_current_user(self, token: str) -> UserProfile:
        if token in _revoked_tokens:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked",
            )
        try:
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM],
            )
        except JWTError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token",
            )
        if payload.get("type") != "access":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Not an access token",
            )
        email = payload.get("email")
        user = _mock_users.get(email)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
            )
        return UserProfile(
            user_id=user["user_id"],
            email=user["email"],
            created_at=user["created_at"],
            scan_count=user["scan_count"],
            subscription_tier=user["subscription_tier"],
        )

    # ------------------------------------------------------------------ #
    #  Cognito helpers                                                     #
    # ------------------------------------------------------------------ #

    def _cognito_register(self, email: str, password: str) -> AuthResponse:
        from app.core.aws import get_cognito_client, get_dynamodb_resource

        cognito = get_cognito_client()
        try:
            resp = cognito.sign_up(
                ClientId=settings.COGNITO_CLIENT_ID,
                Username=email,
                Password=password,
                UserAttributes=[{"Name": "email", "Value": email}],
            )
        except cognito.exceptions.UsernameExistsException:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered",
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            )

        user_id = resp["UserSub"]
        now = datetime.now(timezone.utc).isoformat()

        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
        table.put_item(
            Item={
                "PK": f"USER#{user_id}",
                "SK": "PROFILE",
                "email": email,
                "created_at": now,
                "last_login": now,
                "scan_count": 0,
                "subscription_tier": "free",
            }
        )
        return _make_tokens(user_id, email)

    def _cognito_login(self, email: str, password: str) -> AuthResponse:
        from app.core.aws import get_cognito_client

        cognito = get_cognito_client()
        try:
            resp = cognito.initiate_auth(
                AuthFlow="USER_PASSWORD_AUTH",
                AuthParameters={"USERNAME": email, "PASSWORD": password},
                ClientId=settings.COGNITO_CLIENT_ID,
            )
        except cognito.exceptions.NotAuthorizedException:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials",
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            )

        result = resp["AuthenticationResult"]
        access_token = result["AccessToken"]
        refresh_token = result.get("RefreshToken", "")
        expires_in = result.get("ExpiresIn", settings.TOKEN_EXPIRE_DAYS * 24 * 3600)
        return AuthResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=expires_in,
            user_id=payload["sub"],
            email=payload["email"],
        )

    def _cognito_logout(self, access_token: str) -> None:
        from app.core.aws import get_cognito_client

        cognito = get_cognito_client()
        try:
            cognito.global_sign_out(AccessToken=access_token)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            )

    def _cognito_refresh(self, refresh_token: str) -> AuthResponse:
        from app.core.aws import get_cognito_client

        cognito = get_cognito_client()
        try:
            resp = cognito.initiate_auth(
                AuthFlow="REFRESH_TOKEN_AUTH",
                AuthParameters={"REFRESH_TOKEN": refresh_token},
                ClientId=settings.COGNITO_CLIENT_ID,
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=str(exc),
            )
        result = resp["AuthenticationResult"]
        return AuthResponse(
            access_token=result["AccessToken"],
            refresh_token=refresh_token,
            expires_in=result.get("ExpiresIn", settings.TOKEN_EXPIRE_DAYS * 24 * 3600),
            user_id=payload["sub"],
            email=payload["email"],
        )

    def _cognito_verify_email(self, email: str, code: str) -> None:
        from app.core.aws import get_cognito_client

        cognito = get_cognito_client()
        try:
            cognito.confirm_sign_up(
                ClientId=settings.COGNITO_CLIENT_ID,
                Username=email,
                ConfirmationCode=code,
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            )

    def _cognito_get_current_user(self, token: str) -> UserProfile:
        from app.core.aws import get_dynamodb_resource

        try:
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM],
            )
        except JWTError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token",
            )

        user_id = payload.get("sub")
        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
        resp = table.get_item(Key={"PK": f"USER#{user_id}", "SK": "PROFILE"})
        item = resp.get("Item")
        if not item:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
            )
        return UserProfile(
            user_id=user_id,
            email=item["email"],
            created_at=item["created_at"],
            scan_count=item.get("scan_count", 0),
            subscription_tier=item.get("subscription_tier", "free"),
        )

    # ------------------------------------------------------------------ #
    #  Public API                                                          #
    # ------------------------------------------------------------------ #

    async def register(self, email: str, password: str) -> AuthResponse:
        """Register a new user."""
        if settings.USE_MOCK_AUTH:
            return self._mock_register(email, password)
        return self._cognito_register(email, password)

    async def login(self, email: str, password: str) -> AuthResponse:
        """Authenticate and return tokens."""
        if settings.USE_MOCK_AUTH:
            return self._mock_login(email, password)
        return self._cognito_login(email, password)

    async def logout(self, access_token: str) -> None:
        """Invalidate the current session."""
        if settings.USE_MOCK_AUTH:
            return self._mock_logout(access_token)
        return self._cognito_logout(access_token)

    async def refresh_token(self, refresh_token: str) -> AuthResponse:
        """Exchange a refresh token for a new token pair."""
        if settings.USE_MOCK_AUTH:
            return self._mock_refresh(refresh_token)
        return self._cognito_refresh(refresh_token)

    async def verify_email(self, email: str, code: str) -> None:
        """Confirm email verification code."""
        if settings.USE_MOCK_AUTH:
            return self._mock_verify_email(email, code)
        return self._cognito_verify_email(email, code)

    async def get_current_user(self, token: str) -> UserProfile:
        """Decode token and return the user profile."""
        if settings.USE_MOCK_AUTH:
            return self._mock_get_current_user(token)
        return self._cognito_get_current_user(token)


auth_service = AuthService()
