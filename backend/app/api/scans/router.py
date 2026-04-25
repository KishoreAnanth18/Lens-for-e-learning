"""Scans router — handles image upload and scan initiation."""

import uuid

from fastapi import APIRouter, Depends, Request

from app.api.auth.dependencies import get_current_user
from app.api.auth.models import UserProfile
from app.api.scans.models import ScanRequest, ScanResponse
from app.api.scans.service import (
    create_scan_record,
    upload_to_s3,
    validate_image_format,
    validate_image_size,
)

router = APIRouter(prefix="/scans", tags=["scans"])


@router.post("", response_model=ScanResponse)
async def create_scan(
    body: ScanRequest,
    request: Request,
    current_user: UserProfile = Depends(get_current_user),
) -> ScanResponse:
    """Upload an image and initiate the scan processing pipeline."""
    validate_image_format(body.image_format)
    validate_image_size(body.image_data)

    scan_id = str(uuid.uuid4())
    ext = body.image_format.lower()
    s3_key = f"scans/{body.user_id}/{scan_id}/original.{ext}"

    upload_url = upload_to_s3(scan_id, body.user_id, body.image_data, body.image_format)
    create_scan_record(scan_id, body.user_id, s3_key)

    return ScanResponse(
        scan_id=scan_id,
        status="processing",
        upload_url=upload_url,
        estimated_time=30,
    )
