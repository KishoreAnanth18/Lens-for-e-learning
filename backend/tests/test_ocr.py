"""Tests for the OCR processor module."""

import json
from io import BytesIO
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

from app.api.scans.lambda_handler import ocr_handler
from app.api.scans.ocr import (
    OCREvent,
    OCRResult,
    preprocess_image,
    process_ocr_event,
    run_tesseract_ocr,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_image_bytes(mode: str = "RGB", size: tuple = (100, 100)) -> bytes:
    """Create a minimal in-memory PNG image and return its bytes."""
    img = Image.new(mode, size, color=128)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_ocr_event(**kwargs) -> OCREvent:
    defaults = {
        "scan_id": "scan-123",
        "user_id": "user-456",
        "image_s3_key": "scans/user-456/scan-123/original.png",
    }
    defaults.update(kwargs)
    return OCREvent(**defaults)


LONG_TEXT = "A" * 60  # 60 chars — passes the 50-char minimum


# ---------------------------------------------------------------------------
# preprocess_image
# ---------------------------------------------------------------------------

class TestPreprocessImage:
    def test_returns_pil_image(self):
        result = preprocess_image(_make_image_bytes())
        assert isinstance(result, Image.Image)

    def test_output_is_grayscale(self):
        result = preprocess_image(_make_image_bytes(mode="RGB"))
        assert result.mode == "L"

    def test_accepts_already_grayscale_input(self):
        result = preprocess_image(_make_image_bytes(mode="L"))
        assert isinstance(result, Image.Image)
        assert result.mode == "L"


# ---------------------------------------------------------------------------
# run_tesseract_ocr
# ---------------------------------------------------------------------------

class TestRunTesseractOcr:
    def _mock_image_to_data(self, text_words, confidences):
        """Build the dict that pytesseract.image_to_data returns."""
        return {
            "text": text_words,
            "conf": confidences,
        }

    def test_returns_text_and_confidence(self):
        img = Image.new("L", (100, 100))
        mock_data = self._mock_image_to_data(
            ["Hello", "World", ""],
            [90, 80, -1],
        )
        with patch("pytesseract.image_to_data", return_value=mock_data):
            text, score = run_tesseract_ocr(img)

        assert "Hello" in text
        assert "World" in text
        assert 0.0 <= score <= 1.0

    def test_confidence_score_is_average(self):
        img = Image.new("L", (100, 100))
        mock_data = self._mock_image_to_data(["A", "B"], [60, 40])
        with patch("pytesseract.image_to_data", return_value=mock_data):
            _, score = run_tesseract_ocr(img)

        assert abs(score - 0.50) < 0.001  # (60+40)/2 / 100

    def test_empty_image_returns_zero_confidence(self):
        img = Image.new("L", (10, 10))
        mock_data = self._mock_image_to_data([], [])
        with patch("pytesseract.image_to_data", return_value=mock_data):
            text, score = run_tesseract_ocr(img)

        assert score == 0.0

    def test_confidence_score_between_0_and_1(self):
        img = Image.new("L", (100, 100))
        mock_data = self._mock_image_to_data(["word"] * 5, [100, 95, 85, 70, 60])
        with patch("pytesseract.image_to_data", return_value=mock_data):
            _, score = run_tesseract_ocr(img)

        assert 0.0 <= score <= 1.0


# ---------------------------------------------------------------------------
# process_ocr_event
# ---------------------------------------------------------------------------

class TestProcessOcrEvent:
    def _patch_all(self, extracted_text: str, confidence: float = 0.9):
        """Return a context-manager stack that mocks S3, pytesseract, DynamoDB, Lambda."""
        s3_mock = MagicMock()
        s3_mock.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image_bytes())}

        ddb_mock = MagicMock()
        table_mock = MagicMock()
        ddb_mock.Table.return_value = table_mock

        lambda_mock = MagicMock()

        ocr_data = {
            "text": extracted_text.split(),
            "conf": [90] * len(extracted_text.split()),
        }

        return (
            patch("app.api.scans.ocr.get_s3_client", return_value=s3_mock),
            patch("app.api.scans.ocr.get_dynamodb_resource", return_value=ddb_mock),
            patch("app.api.scans.ocr.get_lambda_client", return_value=lambda_mock),
            patch("pytesseract.image_to_data", return_value=ocr_data),
            table_mock,
            lambda_mock,
        )

    def test_raises_value_error_when_text_too_short(self):
        short_text = "Too short"  # < 50 chars
        patches = self._patch_all(short_text)
        p_s3, p_ddb, p_lam, p_tess, _, _ = patches

        with p_s3, p_ddb, p_lam, p_tess:
            with pytest.raises(ValueError, match="Insufficient text extracted"):
                process_ocr_event(_make_ocr_event())

    def test_success_returns_ocr_result(self):
        patches = self._patch_all(LONG_TEXT)
        p_s3, p_ddb, p_lam, p_tess, _, _ = patches

        with p_s3, p_ddb, p_lam, p_tess:
            result = process_ocr_event(_make_ocr_event())

        assert isinstance(result, OCRResult)
        assert result.character_count >= 50
        assert 0.0 <= result.confidence_score <= 1.0
        assert result.processed_at  # non-empty ISO timestamp

    def test_stores_ocr_data_in_dynamodb(self):
        patches = self._patch_all(LONG_TEXT)
        p_s3, p_ddb, p_lam, p_tess, table_mock, _ = patches

        with p_s3, p_ddb, p_lam, p_tess:
            process_ocr_event(_make_ocr_event(scan_id="scan-abc"))

        # put_item called for OCR_DATA
        put_calls = table_mock.put_item.call_args_list
        assert len(put_calls) == 1
        item = put_calls[0].kwargs["Item"]
        assert item["PK"] == "SCAN#scan-abc"
        assert item["SK"] == "OCR_DATA"
        assert "extracted_text" in item
        assert "confidence_score" in item

    def test_updates_scan_status_to_ocr_complete(self):
        patches = self._patch_all(LONG_TEXT)
        p_s3, p_ddb, p_lam, p_tess, table_mock, _ = patches

        with p_s3, p_ddb, p_lam, p_tess:
            process_ocr_event(_make_ocr_event(scan_id="scan-abc"))

        update_calls = table_mock.update_item.call_args_list
        assert len(update_calls) == 1
        call_kwargs = update_calls[0].kwargs
        assert call_kwargs["Key"] == {"PK": "SCAN#scan-abc", "SK": "METADATA"}
        assert ":s" in call_kwargs["ExpressionAttributeValues"]
        assert call_kwargs["ExpressionAttributeValues"][":s"] == "ocr_complete"

    def test_invokes_nlp_lambda_asynchronously(self):
        patches = self._patch_all(LONG_TEXT)
        p_s3, p_ddb, p_lam, p_tess, _, lambda_mock = patches

        with p_s3, p_ddb, p_lam, p_tess:
            process_ocr_event(_make_ocr_event(scan_id="scan-abc", user_id="user-xyz"))

        lambda_mock.invoke.assert_called_once()
        call_kwargs = lambda_mock.invoke.call_args.kwargs
        assert call_kwargs["InvocationType"] == "Event"
        payload = json.loads(call_kwargs["Payload"])
        assert payload["scan_id"] == "scan-abc"
        assert payload["user_id"] == "user-xyz"

    def test_raises_runtime_error_on_s3_failure(self):
        s3_mock = MagicMock()
        s3_mock.get_object.side_effect = Exception("S3 unavailable")

        with patch("app.api.scans.ocr.get_s3_client", return_value=s3_mock):
            with pytest.raises(RuntimeError, match="Failed to download image from S3"):
                process_ocr_event(_make_ocr_event())


# ---------------------------------------------------------------------------
# ocr_handler (Lambda entry point)
# ---------------------------------------------------------------------------

class TestOcrHandler:
    def _valid_event(self) -> dict:
        return {
            "scan_id": "scan-999",
            "user_id": "user-111",
            "image_s3_key": "scans/user-111/scan-999/original.png",
        }

    def test_returns_200_on_success(self):
        mock_result = OCRResult(
            extracted_text=LONG_TEXT,
            confidence_score=0.92,
            character_count=len(LONG_TEXT),
            processed_at="2024-01-01T00:00:00+00:00",
        )
        with patch("app.api.scans.lambda_handler.process_ocr_event", return_value=mock_result):
            response = ocr_handler(self._valid_event(), None)

        assert response["statusCode"] == 200
        body = response["body"]
        assert body["extracted_text"] == LONG_TEXT
        assert body["confidence_score"] == 0.92

    def test_returns_422_on_insufficient_text(self):
        with patch(
            "app.api.scans.lambda_handler.process_ocr_event",
            side_effect=ValueError("Insufficient text extracted: 10 characters"),
        ):
            response = ocr_handler(self._valid_event(), None)

        assert response["statusCode"] == 422
        assert response["body"]["error"] == "ocr_validation_error"
        assert "Insufficient text" in response["body"]["message"]

    def test_returns_500_on_runtime_error(self):
        with patch(
            "app.api.scans.lambda_handler.process_ocr_event",
            side_effect=RuntimeError("S3 unavailable"),
        ):
            response = ocr_handler(self._valid_event(), None)

        assert response["statusCode"] == 500
        assert response["body"]["error"] == "ocr_processing_error"

    def test_parses_json_string_event(self):
        mock_result = OCRResult(
            extracted_text=LONG_TEXT,
            confidence_score=0.88,
            character_count=len(LONG_TEXT),
            processed_at="2024-01-01T00:00:00+00:00",
        )
        with patch("app.api.scans.lambda_handler.process_ocr_event", return_value=mock_result):
            response = ocr_handler(json.dumps(self._valid_event()), None)

        assert response["statusCode"] == 200

    def test_parses_event_fields_correctly(self):
        """Verify the OCREvent is constructed with the right fields from the raw event."""
        captured = {}

        def capture_event(evt: OCREvent) -> OCRResult:
            captured["event"] = evt
            return OCRResult(
                extracted_text=LONG_TEXT,
                confidence_score=0.9,
                character_count=len(LONG_TEXT),
                processed_at="2024-01-01T00:00:00+00:00",
            )

        with patch("app.api.scans.lambda_handler.process_ocr_event", side_effect=capture_event):
            ocr_handler(self._valid_event(), None)

        assert captured["event"].scan_id == "scan-999"
        assert captured["event"].user_id == "user-111"
        assert captured["event"].image_s3_key == "scans/user-111/scan-999/original.png"
