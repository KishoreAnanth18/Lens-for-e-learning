"""Tests for image_processor module (compression, thumbnail, content hash)."""

from io import BytesIO

import pytest
from PIL import Image

from app.api.scans.image_processor import (
    THUMBNAIL_SIZE,
    compress_image,
    compute_content_hash,
    generate_thumbnail,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_image_bytes(mode: str = "RGB", size: tuple = (400, 400), fmt: str = "JPEG") -> bytes:
    img = Image.new(mode, size, color=(100, 150, 200))
    buf = BytesIO()
    img.save(buf, format=fmt)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# compute_content_hash
# ---------------------------------------------------------------------------

class TestComputeContentHash:
    def test_returns_64_char_hex_string(self):
        h = compute_content_hash(b"hello")
        assert len(h) == 64
        assert all(c in "0123456789abcdef" for c in h)

    def test_same_bytes_same_hash(self):
        data = b"some image bytes"
        assert compute_content_hash(data) == compute_content_hash(data)

    def test_different_bytes_different_hash(self):
        assert compute_content_hash(b"abc") != compute_content_hash(b"xyz")

    def test_empty_bytes_returns_known_sha256(self):
        # SHA-256 of empty string is well-known
        expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        assert compute_content_hash(b"") == expected


# ---------------------------------------------------------------------------
# compress_image
# ---------------------------------------------------------------------------

class TestCompressImage:
    def test_returns_bytes(self):
        result = compress_image(_make_image_bytes(), "jpeg")
        assert isinstance(result, bytes)
        assert len(result) > 0

    def test_compressed_size_lte_original(self):
        # Use a large uncompressed PNG to ensure compression wins
        img = Image.new("RGB", (800, 800), color=(200, 100, 50))
        buf = BytesIO()
        img.save(buf, format="BMP")  # BMP is uncompressed — always larger than JPEG
        original = buf.getvalue()
        compressed = compress_image(original, "jpeg")
        assert len(compressed) <= len(original)

    def test_jpeg_output_is_valid_image(self):
        result = compress_image(_make_image_bytes(), "jpeg")
        img = Image.open(BytesIO(result))
        assert img.format == "JPEG"

    def test_png_output_is_valid_image(self):
        result = compress_image(_make_image_bytes(fmt="PNG"), "png")
        img = Image.open(BytesIO(result))
        assert img.format == "PNG"

    def test_rgba_converted_for_jpeg(self):
        rgba_bytes = _make_image_bytes(mode="RGBA", fmt="PNG")
        result = compress_image(rgba_bytes, "jpeg")
        img = Image.open(BytesIO(result))
        assert img.mode == "RGB"

    def test_heic_treated_as_jpeg_output(self):
        # Pillow can't read real HEIC, but we can test with a JPEG input + heic format label
        result = compress_image(_make_image_bytes(), "heic")
        img = Image.open(BytesIO(result))
        assert img.format == "JPEG"


# ---------------------------------------------------------------------------
# generate_thumbnail
# ---------------------------------------------------------------------------

class TestGenerateThumbnail:
    def test_returns_bytes(self):
        result = generate_thumbnail(_make_image_bytes())
        assert isinstance(result, bytes)
        assert len(result) > 0

    def test_thumbnail_is_valid_jpeg(self):
        result = generate_thumbnail(_make_image_bytes())
        img = Image.open(BytesIO(result))
        assert img.format == "JPEG"

    def test_thumbnail_fits_within_200x200(self):
        result = generate_thumbnail(_make_image_bytes(size=(800, 600)))
        img = Image.open(BytesIO(result))
        assert img.width <= THUMBNAIL_SIZE[0]
        assert img.height <= THUMBNAIL_SIZE[1]

    def test_small_image_not_upscaled(self):
        # 50x50 image should stay 50x50 (thumbnail only shrinks, never enlarges)
        result = generate_thumbnail(_make_image_bytes(size=(50, 50)))
        img = Image.open(BytesIO(result))
        assert img.width <= 50
        assert img.height <= 50

    def test_rgba_converted_to_rgb(self):
        rgba_bytes = _make_image_bytes(mode="RGBA", fmt="PNG")
        result = generate_thumbnail(rgba_bytes)
        img = Image.open(BytesIO(result))
        assert img.mode == "RGB"
