"""Bookmark service for persisting saved learning resources."""

import uuid
from datetime import datetime, timezone

from boto3.dynamodb.conditions import Key
from fastapi import HTTPException, status

from app.api.bookmarks.models import BookmarkResponse
from app.core.aws import get_dynamodb_resource
from app.core.config import settings


def _table():
    ddb = get_dynamodb_resource()
    return ddb.Table(settings.DYNAMODB_TABLE_NAME)


def _ensure_scan_owned_by_user(scan_id: str, user_id: str) -> None:
    item = _table().get_item(Key={"PK": f"SCAN#{scan_id}", "SK": "METADATA"}).get("Item")
    if not item or item.get("user_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scan not found")


def create_bookmark(
    *,
    scan_id: str,
    user_id: str,
    resource_type: str,
    resource_url: str,
    resource_title: str,
    resource_description: str,
) -> BookmarkResponse:
    _ensure_scan_owned_by_user(scan_id, user_id)
    existing = _find_existing_bookmark(user_id, resource_url)
    if existing:
        return BookmarkResponse(**existing)

    bookmark_id = str(uuid.uuid4())
    bookmarked_at = datetime.now(timezone.utc).isoformat()
    item = {
        "PK": f"USER#{user_id}",
        "SK": f"BOOKMARK#{bookmark_id}",
        "bookmark_id": bookmark_id,
        "scan_id": scan_id,
        "resource_type": resource_type,
        "resource_url": resource_url,
        "resource_title": resource_title,
        "resource_description": resource_description,
        "bookmarked_at": bookmarked_at,
    }
    _table().put_item(Item=item)
    return BookmarkResponse(**item)


def list_bookmarks(user_id: str) -> list[BookmarkResponse]:
    response = _table().query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").begins_with("BOOKMARK#")
    )
    items = response.get("Items", [])
    items.sort(key=lambda item: item.get("bookmarked_at", ""), reverse=True)
    return [BookmarkResponse(**item) for item in items]


def delete_bookmark(bookmark_id: str, user_id: str) -> None:
    existing = _table().get_item(
        Key={"PK": f"USER#{user_id}", "SK": f"BOOKMARK#{bookmark_id}"}
    ).get("Item")
    if not existing:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bookmark not found")

    _table().delete_item(Key={"PK": f"USER#{user_id}", "SK": f"BOOKMARK#{bookmark_id}"})


def _find_existing_bookmark(user_id: str, resource_url: str) -> dict | None:
    response = _table().query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").begins_with("BOOKMARK#")
    )
    for item in response.get("Items", []):
        if item.get("resource_url") == resource_url:
            return item
    return None
