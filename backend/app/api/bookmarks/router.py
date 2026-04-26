"""Bookmark routes for saving and listing learning resources."""

from fastapi import APIRouter, Depends, status

from app.api.auth.dependencies import get_current_user
from app.api.auth.models import MessageResponse, UserProfile
from app.api.bookmarks.models import (
    BookmarkCreateRequest,
    BookmarkListResponse,
    BookmarkResponse,
)
from app.api.bookmarks.service import create_bookmark, delete_bookmark, list_bookmarks

scan_router = APIRouter(prefix="/scans", tags=["bookmarks"])
router = APIRouter(prefix="/bookmarks", tags=["bookmarks"])


@scan_router.post("/{scan_id}/bookmarks", response_model=BookmarkResponse)
async def create_scan_bookmark(
    scan_id: str,
    body: BookmarkCreateRequest,
    current_user: UserProfile = Depends(get_current_user),
) -> BookmarkResponse:
    """Create or return an existing bookmark for a scan resource."""
    return create_bookmark(
        scan_id=scan_id,
        user_id=current_user.user_id,
        resource_type=body.resource_type,
        resource_url=body.resource_url,
        resource_title=body.resource_title,
        resource_description=body.resource_description,
    )


@router.get("", response_model=BookmarkListResponse)
async def get_bookmarks(
    current_user: UserProfile = Depends(get_current_user),
) -> BookmarkListResponse:
    """Return all bookmarks for the current user."""
    return BookmarkListResponse(bookmarks=list_bookmarks(current_user.user_id))


@router.delete("/{bookmark_id}", response_model=MessageResponse, status_code=status.HTTP_200_OK)
async def remove_bookmark(
    bookmark_id: str,
    current_user: UserProfile = Depends(get_current_user),
) -> MessageResponse:
    """Delete a bookmark owned by the current user."""
    delete_bookmark(bookmark_id, current_user.user_id)
    return MessageResponse(message="Bookmark deleted successfully")
