"""Upload service for scan image handling."""

import base64
from datetime import datetime, timezone

from fastapi import HTTPException, status

from app.core.aws import get_dynamodb_resource, get_s3_client
from app.core.config import settings

ALLOWED_FORMATS = {"jpeg", "png", "heic"}
MAX_IMAGE_SIZE_BYTES = 2 * 1024 * 1024  # 2MB


def validate_image_format(image_format: str) -> None:
    """Accept only jpeg, png, heic (case-insensitive); raise HTTPException 400 otherwise."""
    if image_format.lower() not in ALLOWED_FORMATS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported image format '{image_format}'. Allowed: jpeg, png, heic",
        )


def validate_image_size(image_data: str) -> None:
    """Decode base64 and check size <= 2MB; raise HTTPException 400 if too large."""
    try:
        decoded = base64.b64decode(image_data)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid base64 image data",
        )
    if len(decoded) > MAX_IMAGE_SIZE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Image size exceeds maximum allowed size of 2MB",
        )


def upload_to_s3(scan_id: str, user_id: str, image_data: str, image_format: str) -> str:
    """Upload decoded image bytes to S3 and return a presigned URL (1 hour expiry)."""
    ext = image_format.lower()
    s3_key = f"scans/{user_id}/{scan_id}/original.{ext}"

    image_bytes = base64.b64decode(image_data)

    content_type_map = {
        "jpeg": "image/jpeg",
        "png": "image/png",
        "heic": "image/heic",
    }
    content_type = content_type_map.get(ext, "application/octet-stream")

    s3 = get_s3_client()
    s3.put_object(
        Bucket=settings.S3_BUCKET_NAME,
        Key=s3_key,
        Body=image_bytes,
        ContentType=content_type,
    )

    presigned_url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET_NAME, "Key": s3_key},
        ExpiresIn=3600,
    )
    return presigned_url


def create_scan_record(scan_id: str, user_id: str, image_s3_key: str) -> dict:
    """Write DynamoDB scan metadata item and return it."""
    now = datetime.now(timezone.utc).isoformat()
    item = {
        "PK": f"SCAN#{scan_id}",
        "SK": "METADATA",
        "GSI1PK": f"USER#{user_id}",
        "GSI1SK": f"SCAN#{now}",
        "scan_id": scan_id,
        "user_id": user_id,
        "status": "processing",
        "image_s3_key": image_s3_key,
        "created_at": now,
        "updated_at": now,
    }

    ddb = get_dynamodb_resource()
    table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
    table.put_item(Item=item)

    return item
