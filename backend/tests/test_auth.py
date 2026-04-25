"""Tests for authentication endpoints (mock mode)."""

import pytest
from fastapi.testclient import TestClient

from app.api.auth.service import _mock_users, _revoked_tokens
from app.core.config import settings
from app.main import app


@pytest.fixture(autouse=True)
def enable_mock_auth(monkeypatch):
    """Force mock auth mode and reset in-memory state before each test."""
    monkeypatch.setattr(settings, "USE_MOCK_AUTH", True)
    _mock_users.clear()
    _revoked_tokens.clear()
    yield


@pytest.fixture
def client():
    return TestClient(app)


# ------------------------------------------------------------------ #
#  Registration                                                        #
# ------------------------------------------------------------------ #

def test_register_success(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={"email": "user@example.com", "password": "Secret123!"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["expires_in"] == settings.TOKEN_EXPIRE_DAYS * 24 * 3600


def test_register_duplicate_returns_409(client):
    payload = {"email": "dup@example.com", "password": "Secret123!"}
    client.post("/api/v1/auth/register", json=payload)
    resp = client.post("/api/v1/auth/register", json=payload)
    assert resp.status_code == 409


# ------------------------------------------------------------------ #
#  Login                                                               #
# ------------------------------------------------------------------ #

def test_login_valid_credentials_returns_tokens(client):
    email, password = "login@example.com", "Pass1234!"
    client.post("/api/v1/auth/register", json={"email": email, "password": password})

    resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert data["expires_in"] == settings.TOKEN_EXPIRE_DAYS * 24 * 3600


def test_login_invalid_credentials_returns_401(client):
    resp = client.post(
        "/api/v1/auth/login",
        json={"email": "nobody@example.com", "password": "wrong"},
    )
    assert resp.status_code == 401


# ------------------------------------------------------------------ #
#  /me                                                                 #
# ------------------------------------------------------------------ #

def test_me_with_valid_token_returns_profile(client):
    email = "me@example.com"
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "Pass1234!"},
    )
    token = reg.json()["access_token"]

    resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["email"] == email
    assert "user_id" in data
    assert "created_at" in data


def test_me_without_token_returns_401(client):
    resp = client.get("/api/v1/auth/me")
    assert resp.status_code == 401


def test_me_with_invalid_token_returns_401(client):
    resp = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": "Bearer invalidtoken"},
    )
    assert resp.status_code == 401


# ------------------------------------------------------------------ #
#  Logout                                                              #
# ------------------------------------------------------------------ #

def test_logout_returns_200(client):
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": "logout@example.com", "password": "Pass1234!"},
    )
    token = reg.json()["access_token"]

    resp = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["message"] == "Logged out successfully"


def test_me_after_logout_returns_401(client):
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": "logoutme@example.com", "password": "Pass1234!"},
    )
    token = reg.json()["access_token"]
    client.post("/api/v1/auth/logout", headers={"Authorization": f"Bearer {token}"})

    resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


# ------------------------------------------------------------------ #
#  Token refresh                                                       #
# ------------------------------------------------------------------ #

def test_refresh_returns_new_tokens(client):
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": "refresh@example.com", "password": "Pass1234!"},
    )
    refresh_token = reg.json()["refresh_token"]

    resp = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data


def test_refresh_with_invalid_token_returns_401(client):
    resp = client.post("/api/v1/auth/refresh", json={"refresh_token": "badtoken"})
    assert resp.status_code == 401
