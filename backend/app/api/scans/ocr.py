"""OCR processor — downloads image from S3, runs Tesseract, stores results in DynamoDB."""

import json
import logging
from datetime import datetime, timezone
from io import BytesIO

import pytesseract
from PIL import Image, ImageEnhance, ImageOps
from pydantic import BaseModel

from app.core.aws import get_dynamodb_resource, get_lambda_client, get_s3_client
from app.core.config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class OCREvent(BaseModel):
    scan_id: str
    user_id: str
    image_s3_key: str


class OCRResult(BaseModel):
    extracted_text: str
    confidence_score: float  # 0.0 – 1.0
    character_count: int
    processed_at: str  # ISO 8601


# ---------------------------------------------------------------------------
# Image preprocessing
# ---------------------------------------------------------------------------

def preprocess_image(image_bytes: bytes) -> Image.Image:
    """Convert image to grayscale and enhance contrast for better OCR accuracy."""
    image = Image.open(BytesIO(image_bytes))
    image = ImageOps.grayscale(image)
    enhancer = ImageEnhance.Contrast(image)
    image = enhancer.enhance(2.0)
    return image


# ---------------------------------------------------------------------------
# Tesseract OCR
# ---------------------------------------------------------------------------

_MOCK_OCR_TEXT = (
    "Machine Learning Fundamentals. "
    "Neural networks are computing systems inspired by biological neural networks "
    "that process information through layers of interconnected nodes called neurons. "
    "Key Concepts: Forward propagation passes inputs through the network. "
    "Backpropagation adjusts weights based on errors. "
    "Activation functions introduce non-linearity into the model. "
    "Loss functions measure prediction accuracy during training. "
    "Deep learning uses multiple hidden layers to learn hierarchical representations. "
    "Common algorithms include gradient descent and stochastic optimization methods."
)


def run_mock_ocr() -> tuple[str, float]:
    """Return pre-canned OCR text for local dev when Tesseract is unavailable."""
    logger.info("Using mock OCR (USE_MOCK_OCR=True or Tesseract not installed)")
    return _MOCK_OCR_TEXT, 0.92


def run_tesseract_ocr(image: Image.Image) -> tuple[str, float]:
    """Run Tesseract on a PIL Image; return (extracted_text, confidence_score 0-1)."""
    custom_config = "--oem 3 --psm 3"
    data = pytesseract.image_to_data(
        image,
        lang="eng",
        config=custom_config,
        output_type=pytesseract.Output.DICT,
    )

    # Filter words with valid confidence (>= 0)
    confidences = [
        int(c) for c in data["conf"] if str(c).lstrip("-").isdigit() and int(c) >= 0
    ]
    words = [
        data["text"][i]
        for i, c in enumerate(data["conf"])
        if str(c).lstrip("-").isdigit() and int(c) >= 0
    ]

    extracted_text = " ".join(w for w in words if w.strip())
    confidence_score = (sum(confidences) / len(confidences) / 100.0) if confidences else 0.0

    return extracted_text, confidence_score


# ---------------------------------------------------------------------------
# Main processing handler
# ---------------------------------------------------------------------------

def process_ocr_event(event: OCREvent, invoke_next_stage: bool = True) -> OCRResult:
    """
    Full OCR pipeline:
    1. Download image from S3
    2. Preprocess image
    3. Run Tesseract OCR
    4. Validate >= 50 characters
    5. Store OCR data in DynamoDB
    6. Update scan metadata status to 'ocr_complete'
    7. Invoke NLP Lambda asynchronously
    """
    scan_id = event.scan_id

    # 1. Download image from S3
    try:
        s3 = get_s3_client()
        response = s3.get_object(Bucket=settings.S3_BUCKET_NAME, Key=event.image_s3_key)
        image_bytes = response["Body"].read()
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] Failed to download image from S3 "
            f"(key={event.image_s3_key}): {exc}"
        ) from exc

    # 2. Preprocess image
    try:
        image = preprocess_image(image_bytes)
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] Image preprocessing failed: {exc}"
        ) from exc

    # 3. Run OCR
    try:
        if settings.USE_MOCK_OCR:
            extracted_text, confidence_score = run_mock_ocr()
        else:
            try:
                extracted_text, confidence_score = run_tesseract_ocr(image)
            except Exception as exc:
                # Auto-fallback to mock if Tesseract is not installed and we're in local dev
                err_str = str(exc).lower()
                if (
                    settings.ENVIRONMENT == "development"
                    and ("tesseract is not installed" in err_str or "not in your path" in err_str)
                ):
                    logger.warning(
                        "[scan_id=%s] Tesseract not found — falling back to mock OCR for local dev",
                        scan_id,
                    )
                    extracted_text, confidence_score = run_mock_ocr()
                else:
                    raise RuntimeError(
                        f"[scan_id={scan_id}] Tesseract OCR failed: {exc}"
                    ) from exc
    except RuntimeError:
        raise
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] Tesseract OCR failed: {exc}"
        ) from exc

    # 4. Validate minimum character count
    character_count = len(extracted_text.strip())
    if character_count < 50:
        raise ValueError(
            f"[scan_id={scan_id}] Insufficient text extracted: "
            f"{character_count} characters (minimum 50 required)"
        )

    processed_at = datetime.now(timezone.utc).isoformat()

    # 5 & 6. Store OCR data and update scan metadata in DynamoDB
    try:
        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)

        # Store OCR data entity
        table.put_item(
            Item={
                "PK": f"SCAN#{scan_id}",
                "SK": "OCR_DATA",
                "extracted_text": extracted_text,
                "confidence_score": str(round(confidence_score, 4)),
                "character_count": character_count,
                "processed_at": processed_at,
            }
        )

        # Update scan metadata status
        table.update_item(
            Key={"PK": f"SCAN#{scan_id}", "SK": "METADATA"},
            UpdateExpression="SET #s = :s, updated_at = :u",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": "ocr_complete",
                ":u": processed_at,
            },
        )
    except Exception as exc:
        raise RuntimeError(
            f"[scan_id={scan_id}] DynamoDB write failed: {exc}"
        ) from exc

    if invoke_next_stage:
        # 7. Invoke NLP Lambda asynchronously
        try:
            lambda_client = get_lambda_client()
            nlp_payload = {
                "scan_id": scan_id,
                "user_id": event.user_id,
                "extracted_text": extracted_text,
            }
            lambda_client.invoke(
                FunctionName=settings.NLP_LAMBDA_NAME,
                InvocationType="Event",  # async
                Payload=json.dumps(nlp_payload).encode(),
            )
        except Exception as exc:
            # Log but don't fail — OCR work is already persisted
            logger.warning(
                "[scan_id=%s] Failed to invoke NLP Lambda (%s): %s",
                scan_id,
                settings.NLP_LAMBDA_NAME,
                exc,
            )

    return OCRResult(
        extracted_text=extracted_text,
        confidence_score=round(confidence_score, 4),
        character_count=character_count,
        processed_at=processed_at,
    )
