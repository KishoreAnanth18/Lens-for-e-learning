"""Pydantic models for bookmark persistence and API responses."""

from typing import Literal

from pydantic import BaseModel, Field


ResourceType = Literal["video", "article", "website"]


class BookmarkCreateRequest(BaseModel):
    resource_type: ResourceType
    resource_url: str
    resource_title: str
    resource_description: str


class BookmarkResponse(BaseModel):
    bookmark_id: str
    scan_id: str
    resource_type: ResourceType
    resource_url: str
    resource_title: str
    resource_description: str
    bookmarked_at: str


class BookmarkListResponse(BaseModel):
    bookmarks: list[BookmarkResponse] = Field(default_factory=list)
