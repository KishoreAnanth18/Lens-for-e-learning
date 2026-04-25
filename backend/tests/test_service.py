"""Tests for the scan service module (upload, duplicate detection, record creation)."""

import base64
from io import BytesIO
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

from app.api.scans.service import (
    create_scan_record,
    find_duplicate_scan,
    upload_to_s3,
    validate_image_format,
    validate_image_size,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_b64_image(size: tuple = (100, 100)) -> str:
    img = Image.new("RGB", size, color=(100, 150, 200))
    buf = BytesIO()
    img.save(buf, format="JPEG")
    return base64.b64encode(buf.getvalue()).decode()


# ---------------------------------------------------------------------------
# validate_image_format
# ---------------------------------------------------------------------------

class TestValidateImageFormat:
    def test_accepts_jpeg(self):
        validate_image_format("jpeg")  # no exception

    def test_accepts_png(self):
        validate_image_format("png")

    def test_accepts_heic(self):
        validate_image_format("heic")

    def test_rejects_gif(self):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc_info:
            validate_image_format("gif")
        assert exc_info.value.status_code == 400

    def test_case_insensitive(self):
        validate_image_format("JPEG")  # no exception


# ---------------------------------------------------------------------------
# validate_image_size
# ---------------------------------------------------------------------------

class TestValidateImageSize:
    def test_accepts_small_image(self):
        data = base64.b64encode(b"x" * 100).decode()
        validate_image_size(data)  # no exception

    def test_rejects_oversized_image(self):
        from fastapi import HTTPException
        data = base64.b64encode(b"x" * (2 * 1024 * 1024 + 1)).decode()
        with pytest.raises(HTTPException) as exc_info:
            validate_image_size(data)
        assert exc_info.value.status_code == 400

    def test_rejects_invalid_base64(self):
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc_info:
            validate_image_size("not-valid-base64!!!")
        assert exc_info.value.status_code == 400


# ---------------------------------------------------------------------------
# find_duplicate_scan
# ---------------------------------------------------------------------------

class TestFindDuplicateScan:
    def _make_table_mock(self, items: list) -> MagicMock:
        table = MagicMock()
        table.query.return_value = {"Items": items}
        ddb = MagicMock()
        ddb.Table.return_value = table
        return ddb

    def test_returns_none_when_no_duplicate(self):
        ddb = self._make_table_mock([])
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            result = find_duplicate_scan("user-1", "abc123")
        assert result is None

    def test_returns_item_when_duplicate_found(self):
        existing = {"scan_id": "scan-old", "status": "complete", "content_hash": "abc123"}
        ddb = self._make_table_mock([existing])
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            result = find_duplicate_scan("user-1", "abc123")
        assert result == existing

    def test_queries_correct_gsi_and_filters(self):
        ddb = self._make_table_mock([])
        table = ddb.Table.return_value
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            find_duplicate_scan("user-42", "hashvalue")
        call_kwargs = table.query.call_args.kwargs
        assert call_kwargs["IndexName"] == "GSI1"
        assert ":pk" in call_kwargs["ExpressionAttributeValues"]
        assert call_kwargs["ExpressionAttributeValues"][":pk"] == "USER#user-42"
        assert call_kwargs["ExpressionAttributeValues"][":hash"] == "hashvalue"
        assert call_kwargs["ExpressionAttributeValues"][":status"] == "complete"


# ---------------------------------------------------------------------------
# upload_to_s3
# ---------------------------------------------------------------------------

class TestUploadToS3:
    def _make_s3_mock(self) -> MagicMock:
        s3 = MagicMock()
        s3.generate_presigned_url.return_value = "https://s3.example.com/presigned"
        return s3

    def test_returns_presigned_url(self):
        s3 = self._make_s3_mock()
        with patch("app.api.scans.service.get_s3_client", return_value=s3):
            url = upload_to_s3("scan-1", "user-1", _make_b64_image(), "jpeg")
        assert url == "https://s3.example.com/presigned"

    def test_uploads_original_and_thumbnail(self):
        s3 = self._make_s3_mock()
        with patch("app.api.scans.service.get_s3_client", return_value=s3):
            upload_to_s3("scan-1", "user-1", _make_b64_image(), "jpeg")
        assert s3.put_object.call_count == 2
        keys = [call.kwargs["Key"] for call in s3.put_object.call_args_list]
        assert any("original" in k for k in keys)
        assert any("thumbnail" in k for k in keys)

    def test_thumbnail_key_ends_with_jpg(self):
        s3 = self._make_s3_mock()
        with patch("app.api.scans.service.get_s3_client", return_value=s3):
            upload_to_s3("scan-1", "user-1", _make_b64_image(), "jpeg")
        keys = [call.kwargs["Key"] for call in s3.put_object.call_args_list]
        thumbnail_keys = [k for k in keys if "thumbnail" in k]
        assert thumbnail_keys[0].endswith(".jpg")


# ---------------------------------------------------------------------------
# create_scan_record
# ---------------------------------------------------------------------------

class TestCreateScanRecord:
    def _make_ddb_mock(self) -> MagicMock:
        table = MagicMock()
        ddb = MagicMock()
        ddb.Table.return_value = table
        return ddb, table

    def test_stores_content_hash_when_provided(self):
        ddb, table = self._make_ddb_mock()
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            create_scan_record("scan-1", "user-1", "scans/user-1/scan-1/original.jpeg", content_hash="abc")
        item = table.put_item.call_args.kwargs["Item"]
        assert item["content_hash"] == "abc"

    def test_omits_content_hash_when_not_provided(self):
        ddb, table = self._make_ddb_mock()
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            create_scan_record("scan-1", "user-1", "scans/user-1/scan-1/original.jpeg")
        item = table.put_item.call_args.kwargs["Item"]
        assert "content_hash" not in item

    def test_includes_thumbnail_key(self):
        ddb, table = self._make_ddb_mock()
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            create_scan_record("scan-1", "user-1", "scans/user-1/scan-1/original.jpeg")
        item = table.put_item.call_args.kwargs["Item"]
        assert "image_thumbnail_key" in item
        assert item["image_thumbnail_key"].endswith("thumbnail.jpg")

    def test_sets_status_to_processing(self):
        ddb, table = self._make_ddb_mock()
        with patch("app.api.scans.service.get_dynamodb_resource", return_value=ddb):
            create_scan_record("scan-1", "user-1", "scans/user-1/scan-1/original.jpeg")
        item = table.put_item.call_args.kwargs["Item"]
        assert item["status"] == "processing"
