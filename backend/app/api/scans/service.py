"""Upload service for scan image handling."""

import base64
import json
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import HTTPException, status

from app.api.scans.image_processor import (
    compress_image,
    compute_content_hash,
    generate_thumbnail,
)
from app.api.scans.nlp import NLPEvent, process_nlp_event
from app.api.scans.ocr import OCREvent, process_ocr_event
from app.api.scans.search import SearchEvent, process_search_event
from app.core.aws import get_dynamodb_resource, get_s3_client
from app.core.config import settings

ALLOWED_FORMATS = {"jpeg", "png", "heic"}
MAX_IMAGE_SIZE_BYTES = 2 * 1024 * 1024  # 2MB

logger = logging.getLogger(__name__)


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
            detail="Image size exceeds maximum allowed size of 2MB",
        )


def find_duplicate_scan(user_id: str, content_hash: str) -> Optional[dict]:
    """
    Check if a completed scan with the same content hash already exists for this user.
    Queries the GSI1 index (USER#<user_id>) and filters by content_hash.
    Returns the existing scan item if found, else None.
    """
    ddb = get_dynamodb_resource()
    table = ddb.Table(settings.DYNAMODB_TABLE_NAME)

    response = table.query(
        IndexName="GSI1",
        KeyConditionExpression="GSI1PK = :pk",
        FilterExpression="#s = :status AND content_hash = :hash",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":pk": f"USER#{user_id}",
            ":status": "complete",
            ":hash": content_hash,
        },
    )
    items = response.get("Items", [])
    return items[0] if items else None


def upload_to_s3(
    scan_id: str,
    user_id: str,
    image_data: str,
    image_format: str,
) -> str:
    """
    Compress image, upload original + thumbnail to S3, return presigned URL (1 hour).
    """
    ext = image_format.lower()
    image_bytes = base64.b64decode(image_data)

    # Compress before storing
    compressed_bytes = compress_image(image_bytes, image_format)
    thumbnail_bytes = generate_thumbnail(image_bytes)

    content_type_map = {
        "jpeg": "image/jpeg",
        "png": "image/png",
        "heic": "image/heic",
    }
    content_type = content_type_map.get(ext, "application/octet-stream")

    original_key = f"scans/{user_id}/{scan_id}/original.{ext}"
    thumbnail_key = f"scans/{user_id}/{scan_id}/thumbnail.jpg"

    s3 = get_s3_client()
    s3.put_object(
        Bucket=settings.S3_BUCKET_NAME,
        Key=original_key,
        Body=compressed_bytes,
        ContentType=content_type,
    )
    s3.put_object(
        Bucket=settings.S3_BUCKET_NAME,
        Key=thumbnail_key,
        Body=thumbnail_bytes,
        ContentType="image/jpeg",
    )

    presigned_url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET_NAME, "Key": original_key},
        ExpiresIn=3600,
    )
    return presigned_url


def create_scan_record(
    scan_id: str,
    user_id: str,
    image_s3_key: str,
    content_hash: Optional[str] = None,
) -> dict:
    """Write DynamoDB scan metadata item and return it."""
    now = datetime.now(timezone.utc).isoformat()
    thumbnail_key = f"scans/{user_id}/{scan_id}/thumbnail.jpg"
    item = {
        "PK": f"SCAN#{scan_id}",
        "SK": "METADATA",
        "GSI1PK": f"USER#{user_id}",
        "GSI1SK": f"SCAN#{now}",
        "scan_id": scan_id,
        "user_id": user_id,
        "status": "processing",
        "image_s3_key": image_s3_key,
        "image_thumbnail_key": thumbnail_key,
        "error_message": None,
        "created_at": now,
        "updated_at": now,
    }
    if content_hash:
        item["content_hash"] = content_hash

    ddb = get_dynamodb_resource()
    table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
    table.put_item(Item=item)

    return item


def trigger_scan_processing(scan_id: str, user_id: str, image_s3_key: str) -> None:
    """Start the OCR stage, using local in-process orchestration in development."""
    if settings.USE_LOCALSTACK or settings.ENVIRONMENT == "development":
        _run_scan_pipeline_locally(scan_id, user_id, image_s3_key)
        return

    try:
        from app.core.aws import get_lambda_client

        lambda_client = get_lambda_client()
        payload = {
            "scan_id": scan_id,
            "user_id": user_id,
            "image_s3_key": image_s3_key,
        }
        lambda_client.invoke(
            FunctionName=settings.OCR_LAMBDA_NAME,
            InvocationType="Event",
            Payload=json.dumps(payload).encode(),
        )
    except Exception as exc:
        _mark_scan_failed(scan_id, "OCR", str(exc))
        raise


def _run_scan_pipeline_locally(scan_id: str, user_id: str, image_s3_key: str) -> None:
    """Execute the full OCR -> NLP -> Search chain in-process for local development."""
    try:
        ocr_result = process_ocr_event(
            OCREvent(scan_id=scan_id, user_id=user_id, image_s3_key=image_s3_key),
            invoke_next_stage=False,
        )
        nlp_result = process_nlp_event(
            NLPEvent(
                scan_id=scan_id,
                user_id=user_id,
                extracted_text=ocr_result.extracted_text,
            ),
            invoke_next_stage=False,
        )
        process_search_event(
            SearchEvent(
                scan_id=scan_id,
                user_id=user_id,
                keywords=nlp_result.keywords,
                summary=nlp_result.summary,
            )
        )
    except Exception as exc:
        stage = _infer_failed_stage(exc)
        logger.exception("[scan_id=%s] Local pipeline failed during %s", scan_id, stage)
        _mark_scan_failed(scan_id, stage, str(exc))


def _infer_failed_stage(exc: Exception) -> str:
    message = str(exc).lower()
    if "keyword" in message or "summary" in message or "nlp" in message:
        return "NLP"
    if "search" in message:
        return "Search"
    return "OCR"


def _mark_scan_failed(scan_id: str, stage: str, error_message: str) -> None:
    ddb = get_dynamodb_resource()
    table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
    table.update_item(
        Key={"PK": f"SCAN#{scan_id}", "SK": "METADATA"},
        UpdateExpression="SET #s = :s, error_message = :e, updated_at = :u",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": "failed",
            ":e": f"{stage} failed: {error_message}",
            ":u": datetime.now(timezone.utc).isoformat(),
        },
    )


def get_scan_status(scan_id: str, user_id: str) -> dict:
    """Return scan metadata plus any persisted OCR/NLP/search output."""
    ddb = get_dynamodb_resource()
    table = ddb.Table(settings.DYNAMODB_TABLE_NAME)

    metadata = table.get_item(Key={"PK": f"SCAN#{scan_id}", "SK": "METADATA"}).get("Item")
    if not metadata:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scan not found")
    if metadata.get("user_id") != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Scan not found")

    ocr_item = table.get_item(Key={"PK": f"SCAN#{scan_id}", "SK": "OCR_DATA"}).get("Item", {})
    nlp_item = table.get_item(Key={"PK": f"SCAN#{scan_id}", "SK": "NLP_DATA"}).get("Item", {})
    results_item = table.get_item(Key={"PK": f"SCAN#{scan_id}", "SK": "RESULTS"}).get("Item", {})

    return {
        "scan_id": scan_id,
        "status": metadata.get("status", "processing"),
        "created_at": metadata.get("created_at"),
        "updated_at": metadata.get("updated_at"),
        "image_thumbnail_key": metadata.get("image_thumbnail_key"),
        "error_message": metadata.get("error_message"),
        "extracted_text": ocr_item.get("extracted_text"),
        "summary": nlp_item.get("summary"),
        "keywords": nlp_item.get("keywords", []),
        "videos": results_item.get("videos", []),
        "articles": results_item.get("articles", []),
        "websites": results_item.get("websites", []),
    }
