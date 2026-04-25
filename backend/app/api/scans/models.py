"""Pydantic models for scan request/response validation."""

from pydantic import BaseModel


class ScanRequest(BaseModel):
    image_data: str  # Base64 encoded image
    image_format: str  # jpeg, png, heic
    user_id: str


class ScanResponse(BaseModel):
    scan_id: str
    status: str
    upload_url: str
    estimated_time: int  # seconds


class ErrorResponse(BaseModel):
    error_code: str
    message: str
    request_id: str
