"""Tests for bookmark endpoints and persistence behavior."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.api.auth.service import _mock_users, _revoked_tokens
from app.core.config import settings
from app.main import app


@pytest.fixture(autouse=True)
def enable_mock_auth(monkeypatch):
    monkeypatch.setattr(settings, "USE_MOCK_AUTH", True)
    _mock_users.clear()
    _revoked_tokens.clear()
    yield


@pytest.fixture
def client():
    return TestClient(app)


def _auth_header(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": "bookmark@example.com", "password": "Secret123!"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _table_with_scan_and_bookmarks(bookmarks: list[dict] | None = None) -> MagicMock:
    bookmarks = bookmarks or []
    table = MagicMock()

    def get_item(Key):
        if Key == {"PK": "SCAN#scan-123", "SK": "METADATA"}:
            return {"Item": {"PK": "SCAN#scan-123", "SK": "METADATA", "user_id": "user-123"}}
        for item in bookmarks:
            if Key == {"PK": f"USER#user-123", "SK": f"BOOKMARK#{item['bookmark_id']}"}:
                return {"Item": item}
        return {}

    table.get_item.side_effect = get_item
    table.query.return_value = {"Items": bookmarks}
    ddb = MagicMock()
    ddb.Table.return_value = table
    return ddb


def test_create_bookmark_success(client, monkeypatch):
    headers = _auth_header(client)
    _mock_users["bookmark@example.com"]["user_id"] = "user-123"
    ddb = _table_with_scan_and_bookmarks()

    with patch("app.api.bookmarks.service.get_dynamodb_resource", return_value=ddb):
        response = client.post(
            "/api/v1/scans/scan-123/bookmarks",
            json={
                "resource_type": "video",
                "resource_url": "https://example.com/video",
                "resource_title": "Example Video",
                "resource_description": "Helpful explanation",
            },
            headers=headers,
        )

    assert response.status_code == 200
    data = response.json()
    assert data["resource_type"] == "video"
    assert data["resource_url"] == "https://example.com/video"


def test_list_bookmarks_returns_items(client):
    headers = _auth_header(client)
    _mock_users["bookmark@example.com"]["user_id"] = "user-123"
    bookmarks = [
        {
            "bookmark_id": "bookmark-1",
            "scan_id": "scan-123",
            "resource_type": "article",
            "resource_url": "https://example.com/article",
            "resource_title": "Example Article",
            "resource_description": "Detailed notes",
            "bookmarked_at": "2026-04-26T12:00:00+00:00",
        }
    ]
    ddb = _table_with_scan_and_bookmarks(bookmarks)

    with patch("app.api.bookmarks.service.get_dynamodb_resource", return_value=ddb):
        response = client.get("/api/v1/bookmarks", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data["bookmarks"]) == 1
    assert data["bookmarks"][0]["bookmark_id"] == "bookmark-1"


def test_delete_bookmark_success(client):
    headers = _auth_header(client)
    _mock_users["bookmark@example.com"]["user_id"] = "user-123"
    bookmarks = [
        {
            "bookmark_id": "bookmark-1",
            "scan_id": "scan-123",
            "resource_type": "website",
            "resource_url": "https://example.com/site",
            "resource_title": "Example Site",
            "resource_description": "Reference link",
            "bookmarked_at": "2026-04-26T12:00:00+00:00",
        }
    ]
    ddb = _table_with_scan_and_bookmarks(bookmarks)
    table = ddb.Table.return_value

    with patch("app.api.bookmarks.service.get_dynamodb_resource", return_value=ddb):
        response = client.delete("/api/v1/bookmarks/bookmark-1", headers=headers)

    assert response.status_code == 200
    assert response.json()["message"] == "Bookmark deleted successfully"
    table.delete_item.assert_called_once()
