"""Lambda entry points for the OCR and NLP processors."""

import json
import logging

from app.api.scans.nlp import NLPEvent, process_nlp_event
from app.api.scans.ocr import OCREvent, process_ocr_event

logger = logging.getLogger(__name__)


def ocr_handler(event: dict, context) -> dict:
    """
    AWS Lambda handler for OCR processing.

    Expected event payload:
        {
            "scan_id": "<uuid>",
            "user_id": "<uuid>",
            "image_s3_key": "scans/<user_id>/<scan_id>/original.<ext>"
        }
    """
    try:
        # Support both raw dict and JSON-string payloads
        if isinstance(event, str):
            event = json.loads(event)

        ocr_event = OCREvent(**event)
        result = process_ocr_event(ocr_event)

        return {
            "statusCode": 200,
            "body": result.model_dump(),
        }

    except ValueError as exc:
        # Insufficient text / validation errors
        logger.error("OCR validation error: %s", exc)
        return {
            "statusCode": 422,
            "body": {"error": "ocr_validation_error", "message": str(exc)},
        }
    except RuntimeError as exc:
        logger.error("OCR processing error: %s", exc)
        return {
            "statusCode": 500,
            "body": {"error": "ocr_processing_error", "message": str(exc)},
        }
    except Exception as exc:
        logger.exception("Unexpected OCR error: %s", exc)
        return {
            "statusCode": 500,
            "body": {"error": "internal_error", "message": f"Unexpected error: {exc}"},
        }


def nlp_handler(event: dict, context) -> dict:
    """
    AWS Lambda handler for NLP processing.

    Expected event payload:
        {
            "scan_id": "<uuid>",
            "user_id": "<uuid>",
            "extracted_text": "<text from OCR>"
        }
    """
    try:
        if isinstance(event, str):
            event = json.loads(event)

        nlp_event = NLPEvent(**event)
        result = process_nlp_event(nlp_event)

        return {
            "statusCode": 200,
            "body": result.model_dump(),
        }

    except ValueError as exc:
        logger.error("NLP validation error: %s", exc)
        return {
            "statusCode": 422,
            "body": {"error": "nlp_validation_error", "message": str(exc)},
        }
    except RuntimeError as exc:
        logger.error("NLP processing error: %s", exc)
        return {
            "statusCode": 500,
            "body": {"error": "nlp_processing_error", "message": str(exc)},
        }
    except Exception as exc:
        logger.exception("Unexpected NLP error: %s", exc)
        return {
            "statusCode": 500,
            "body": {"error": "internal_error", "message": f"Unexpected error: {exc}"},
        }
