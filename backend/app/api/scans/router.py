"""Scans router - handles image upload, listing, status, and deletion."""

import base64
import json
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, status

from app.api.auth.dependencies import get_current_user
from app.api.auth.models import MessageResponse, UserProfile
from app.api.scans.image_processor import compute_content_hash
from app.api.scans.models import (
    ErrorResponse,
    ScanListResponse,
    ScanRequest,
    ScanResponse,
    ScanStatusResponse,
)
from app.api.scans.service import (
    create_scan_record,
    delete_scan,
    find_duplicate_scan,
    get_scan_status,
    list_scans,
    trigger_scan_processing,
    upload_to_s3,
    validate_image_format,
    validate_image_size,
)

router = APIRouter(prefix="/scans", tags=["scans"])


@router.post(
    "",
    response_model=ScanResponse,
    responses={
        400: {"model": ErrorResponse},
        401: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
    },
)
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
    image_bytes = base64.b64decode(body.image_data)
    content_hash = compute_content_hash(image_bytes)

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


@router.get(
    "",
    response_model=ScanListResponse,
    responses={401: {"model": ErrorResponse}, 429: {"model": ErrorResponse}},
)
async def get_scans(
    limit: int = Query(default=20, ge=1, le=50),
    next_token: str | None = Query(default=None),
    current_user: UserProfile = Depends(get_current_user),
) -> ScanListResponse:
    """List the current user's scans in reverse chronological order."""
    decoded_next = None
    if next_token:
        decoded_next = json.loads(base64.b64decode(next_token).decode())

    result = list_scans(
        current_user.user_id,
        limit=limit,
        next_token=decoded_next,
    )

    encoded_next = None
    if result["next_token"]:
        encoded_next = base64.b64encode(json.dumps(result["next_token"]).encode()).decode()

    return ScanListResponse(scans=result["scans"], next_token=encoded_next)


@router.get(
    "/{scan_id}",
    response_model=ScanStatusResponse,
    responses={
        401: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
    },
)
async def get_scan(
    scan_id: str,
    current_user: UserProfile = Depends(get_current_user),
) -> ScanStatusResponse:
    """Fetch the current status and any available output for a scan."""
    response = get_scan_status(scan_id, current_user.user_id)
    return ScanStatusResponse(**response)


@router.delete(
    "/{scan_id}",
    response_model=MessageResponse,
    status_code=status.HTTP_200_OK,
    responses={
        401: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        429: {"model": ErrorResponse},
    },
)
async def remove_scan(
    scan_id: str,
    current_user: UserProfile = Depends(get_current_user),
) -> MessageResponse:
    """Delete a scan and its related artifacts."""
    delete_scan(scan_id, current_user.user_id)
    return MessageResponse(message="Scan deleted successfully")
