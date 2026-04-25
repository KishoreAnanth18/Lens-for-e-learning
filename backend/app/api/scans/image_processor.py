"""Image compression and thumbnail generation utilities."""

import hashlib
from io import BytesIO

from PIL import Image

THUMBNAIL_SIZE = (200, 200)
JPEG_QUALITY = 85  # Good balance between size and quality


def compute_content_hash(image_bytes: bytes) -> str:
    """Return SHA-256 hex digest of raw image bytes."""
    return hashlib.sha256(image_bytes).hexdigest()


def compress_image(image_bytes: bytes, image_format: str) -> bytes:
    """
    Compress image using Pillow. Returns compressed bytes.
    Compressed size is guaranteed to be <= original size (falls back to original if not).
    """
    fmt = image_format.lower()
    # HEIC is not natively writable by Pillow; treat as JPEG output
    output_format = "JPEG" if fmt in ("jpeg", "heic") else "PNG"

    image = Image.open(BytesIO(image_bytes))

    # Convert RGBA/P to RGB for JPEG compatibility
    if output_format == "JPEG" and image.mode not in ("RGB", "L"):
        image = image.convert("RGB")

    buf = BytesIO()
    if output_format == "JPEG":
        image.save(buf, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    else:
        image.save(buf, format="PNG", optimize=True)

    compressed = buf.getvalue()
    # Only use compressed version if it's actually smaller
    return compressed if len(compressed) < len(image_bytes) else image_bytes


def generate_thumbnail(image_bytes: bytes) -> bytes:
    """Generate a 200x200 JPEG thumbnail from image bytes."""
    image = Image.open(BytesIO(image_bytes))
    if image.mode not in ("RGB", "L"):
        image = image.convert("RGB")
    image.thumbnail(THUMBNAIL_SIZE, Image.LANCZOS)
    buf = BytesIO()
    image.save(buf, format="JPEG", quality=80, optimize=True)
    return buf.getvalue()
