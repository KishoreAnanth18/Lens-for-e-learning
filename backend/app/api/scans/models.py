"""Pydantic models for scan request/response validation."""

from typing import List, Optional

from pydantic import BaseModel, Field

# Re-export NLP models so callers can import from models or nlp directly
from app.api.scans.nlp import NLPEvent, NLPResult  # noqa: F401


class ScanRequest(BaseModel):
    image_data: str  # Base64 encoded image
    image_format: str  # jpeg, png, heic
    user_id: Optional[str] = None


class ScanResponse(BaseModel):
    scan_id: str
    status: str
    upload_url: str
    estimated_time: int  # seconds


class ErrorResponse(BaseModel):
    error_code: str
    message: str
    request_id: str


class ScanResource(BaseModel):
    title: str
    description: str
    url: str


class ScanStatusResponse(BaseModel):
    scan_id: str
    status: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    image_thumbnail_key: Optional[str] = None
    error_message: Optional[str] = None
    extracted_text: Optional[str] = None
    summary: Optional[str] = None
    keywords: List[str] = Field(default_factory=list)
    videos: List[dict] = Field(default_factory=list)
    articles: List[dict] = Field(default_factory=list)
    websites: List[dict] = Field(default_factory=list)
