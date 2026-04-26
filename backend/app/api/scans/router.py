"""Scans router — handles image upload and scan initiation."""

import base64
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Request

from app.api.auth.dependencies import get_current_user
from app.api.auth.models import UserProfile
from app.api.scans.image_processor import compute_content_hash
from app.api.scans.models import ScanRequest, ScanResponse, ScanStatusResponse
from app.api.scans.service import (
    create_scan_record,
    find_duplicate_scan,
    get_scan_status,
    trigger_scan_processing,
    upload_to_s3,
    validate_image_format,
    validate_image_size,
)

router = APIRouter(prefix="/scans", tags=["scans"])


@router.post("", response_model=ScanResponse)
async def create_scan(
    body: ScanRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    current_user: UserProfile = Depends(get_current_user),
) -> ScanResponse:
    """Upload an image and initiate the scan processing pipeline."""
    validate_image_format(body.image_format)
    validate_image_size(body.image_data)

    user_id = current_user.user_id

    # Compute content hash BEFORE uploading to detect duplicates
    image_bytes = base64.b64decode(body.image_data)
    content_hash = compute_content_hash(image_bytes)

    # Check for an existing completed scan with the same image
    duplicate = find_duplicate_scan(user_id, content_hash)
    if duplicate:
        return ScanResponse(
            scan_id=duplicate["scan_id"],
            status="complete",
            upload_url="",
            estimated_time=0,
        )

    scan_id = str(uuid.uuid4())
    ext = body.image_format.lower()
    s3_key = f"scans/{user_id}/{scan_id}/original.{ext}"

    upload_url = upload_to_s3(scan_id, user_id, body.image_data, body.image_format)
    create_scan_record(scan_id, user_id, s3_key, content_hash=content_hash)
    background_tasks.add_task(trigger_scan_processing, scan_id, user_id, s3_key)

    return ScanResponse(
        scan_id=scan_id,
        status="processing",
        upload_url=upload_url,
        estimated_time=30,
    )


@router.get("/{scan_id}", response_model=ScanStatusResponse)
async def get_scan(
    scan_id: str,
    current_user: UserProfile = Depends(get_current_user),
) -> ScanStatusResponse:
    """Fetch the current status and any available output for a scan."""
    response = get_scan_status(scan_id, current_user.user_id)
    return ScanStatusResponse(**response)
