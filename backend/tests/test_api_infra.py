"""Tests for API middleware behavior and scan endpoints."""

import base64
import json
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.api.auth.service import _mock_users, _revoked_tokens
from app.core.config import settings
from app.main import app


@pytest.fixture(autouse=True)
def enable_mock_auth(monkeypatch):
    monkeypatch.setattr(settings, "USE_MOCK_AUTH", True)
    monkeypatch.setattr(settings, "RATE_LIMIT_REQUESTS", 60)
    monkeypatch.setattr(settings, "RATE_LIMIT_WINDOW_SECONDS", 60)
    _mock_users.clear()
    _revoked_tokens.clear()
    yield


@pytest.fixture
def client():
    return TestClient(app)


def _auth_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": "scan-api@example.com", "password": "Secret123!"},
    )
    _mock_users["scan-api@example.com"]["user_id"] = "user-123"
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_validation_errors_return_structured_envelope(client):
    response = client.post("/api/v1/auth/register", json={"email": "bad@example.com"})

    assert response.status_code == 422
    payload = response.json()
    assert payload["error_code"] == "validation_error"
    assert payload["message"] == "Request validation failed"
    assert payload["request_id"]
    assert payload["timestamp"]
    assert "details" in payload
    assert response.headers["X-Request-ID"] == payload["request_id"]


def test_http_errors_return_structured_envelope(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"email": "nobody@example.com", "password": "wrong"},
    )

    assert response.status_code == 401
    payload = response.json()
    assert payload["error_code"] == "unauthorized"
    assert payload["request_id"]
    assert payload["timestamp"]


def test_rate_limit_returns_429(client, monkeypatch):
    monkeypatch.setattr(settings, "RATE_LIMIT_REQUESTS", 1)

    first = client.get("/api/v1/health")
    second = client.get("/api/v1/health")

    assert first.status_code == 200
    assert second.status_code == 429
    payload = second.json()
    assert payload["error_code"] == "rate_limit_exceeded"
    assert payload["details"]["limit"] == 1


def test_list_scans_returns_reverse_chronological_metadata(client):
    headers = _auth_headers(client)
    table = MagicMock()
    table.query.return_value = {
        "Items": [
            {
                "PK": "SCAN#scan-2",
                "SK": "METADATA",
                "scan_id": "scan-2",
                "status": "complete",
                "created_at": "2026-06-01T12:00:00+00:00",
                "updated_at": "2026-06-01T12:05:00+00:00",
                "image_thumbnail_key": "thumb-2.jpg",
                "summary": "Newest summary",
                "error_message": None,
            },
            {
                "PK": "SCAN#scan-1",
                "SK": "METADATA",
                "scan_id": "scan-1",
                "status": "processing",
                "created_at": "2026-05-31T12:00:00+00:00",
                "updated_at": "2026-05-31T12:01:00+00:00",
                "image_thumbnail_key": "thumb-1.jpg",
                "summary": None,
                "error_message": None,
            },
        ]
    }
    ddb = MagicMock()
    ddb.Table.return_value = table

    with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
        response = client.get("/api/v1/scans", headers=headers)

    assert response.status_code == 200
    payload = response.json()
    assert [item["scan_id"] for item in payload["scans"]] == ["scan-2", "scan-1"]
    assert payload["scans"][0]["summary"] == "Newest summary"


def test_list_scans_encodes_next_token(client):
    headers = _auth_headers(client)
    table = MagicMock()
    table.query.return_value = {
        "Items": [],
        "LastEvaluatedKey": {
            "PK": "SCAN#scan-2",
            "SK": "METADATA",
            "GSI1PK": "USER#user-123",
            "GSI1SK": "SCAN#2026-06-01T12:00:00+00:00",
        },
    }
    ddb = MagicMock()
    ddb.Table.return_value = table

    with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
        response = client.get("/api/v1/scans", headers=headers)

    assert response.status_code == 200
    next_token = response.json()["next_token"]
    decoded = json.loads(base64.b64decode(next_token).decode())
    assert decoded["PK"] == "SCAN#scan-2"


def test_delete_scan_removes_records_and_s3_objects(client):
    headers = _auth_headers(client)
    table = MagicMock()
    table.get_item.return_value = {
        "Item": {
            "PK": "SCAN#scan-123",
            "SK": "METADATA",
            "user_id": "user-123",
            "image_s3_key": "scans/user-123/scan-123/original.jpeg",
            "image_thumbnail_key": "scans/user-123/scan-123/thumbnail.jpg",
        }
    }
    ddb = MagicMock()
    ddb.Table.return_value = table
    s3 = MagicMock()

    with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb), patch(
        "app.api.scans.service.get_s3_client",
        return_value=s3,
    ):
        response = client.delete("/api/v1/scans/scan-123", headers=headers)

    assert response.status_code == 200
    assert response.json()["message"] == "Scan deleted successfully"
    assert s3.delete_object.call_count == 2
