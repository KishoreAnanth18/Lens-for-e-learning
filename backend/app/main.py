"""FastAPI application entry point."""

from __future__ import annotations

import logging
import time
import uuid
from collections import defaultdict, deque
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.auth.router import router as auth_router
from app.api.bookmarks.router import router as bookmarks_router
from app.api.bookmarks.router import scan_router as scan_bookmarks_router
from app.api.scans.router import router as scans_router
from app.core.config import settings
from app.core.errors import (
    http_exception_handler,
    json_error_response,
    unhandled_exception_handler,
    validation_exception_handler,
)

logging.basicConfig(level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO))
logger = logging.getLogger("lens.api")

app = FastAPI(
    title="Lens for E-Learning API",
    description="Backend API for Lens for E-Learning MVP",
    version="0.1.0",
)

_rate_limit_buckets: dict[str, deque[float]] = defaultdict(deque)


@app.middleware("http")
async def request_context_middleware(request: Request, call_next):
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    started = time.perf_counter()
    client_host = request.client.host if request.client else "unknown"

    if request.url.path.startswith("/api/v1"):
        bucket_key = f"{client_host}:{request.url.path}"
        window_seconds = settings.RATE_LIMIT_WINDOW_SECONDS
        max_requests = settings.RATE_LIMIT_REQUESTS
        now = time.monotonic()
        bucket = _rate_limit_buckets[bucket_key]

        while bucket and now - bucket[0] > window_seconds:
            bucket.popleft()

        if len(bucket) >= max_requests:
            logger.warning(
                "rate_limit_exceeded request_id=%s client=%s path=%s",
                request_id,
                client_host,
                request.url.path,
            )
            return json_error_response(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                error_code="rate_limit_exceeded",
                message="Too many requests. Please try again later.",
                request_id=request_id,
                details={
                    "limit": max_requests,
                    "window_seconds": window_seconds,
                },
            )

        bucket.append(now)

    try:
        response = await call_next(request)
    except Exception:
        duration_ms = round((time.perf_counter() - started) * 1000, 2)
        logger.exception(
            "request_failed request_id=%s method=%s path=%s duration_ms=%s",
            request_id,
            request.method,
            request.url.path,
            duration_ms,
        )
        raise
    duration_ms = round((time.perf_counter() - started) * 1000, 2)
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Process-Time-Ms"] = str(duration_ms)

    logger.info(
        "request_complete request_id=%s method=%s path=%s status=%s duration_ms=%s timestamp=%s",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
        datetime.now(timezone.utc).isoformat(),
    )
    logger.info(
        "metric=request_count request_id=%s path=%s status=%s duration_ms=%s",
        request_id,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.exception_handler(RequestValidationError)
async def _validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    return await validation_exception_handler(request, exc)


@app.exception_handler(Exception)
async def _unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception(
        "unhandled_exception request_id=%s path=%s",
        getattr(request.state, "request_id", "unknown"),
        request.url.path,
    )
    return await unhandled_exception_handler(request, exc)


@app.exception_handler(HTTPException)
async def _http_error_handler(request: Request, exc: HTTPException) -> JSONResponse:
    return await http_exception_handler(request, exc)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/api/v1")
app.include_router(scans_router, prefix="/api/v1")
app.include_router(scan_bookmarks_router, prefix="/api/v1")
app.include_router(bookmarks_router, prefix="/api/v1")


@app.get("/api/v1/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "environment": settings.ENVIRONMENT,
        "version": "0.1.0",
        "localstack": settings.USE_LOCALSTACK,
    }


@app.get("/api/v1/health/aws")
async def aws_health_check():
    """Check connectivity to AWS services (LocalStack or real AWS)."""
    from app.core.aws import get_dynamodb_resource, get_s3_client

    results: dict = {}

    try:
        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
        table.load()
        results["dynamodb"] = "ok"
    except Exception as exc:
        results["dynamodb"] = f"error: {exc}"

    try:
        s3 = get_s3_client()
        s3.head_bucket(Bucket=settings.S3_BUCKET_NAME)
        results["s3"] = "ok"
    except Exception as exc:
        results["s3"] = f"error: {exc}"

    all_ok = all(v == "ok" for v in results.values())
    return {
        "status": "healthy" if all_ok else "degraded",
        "services": results,
        "endpoint": settings.aws_endpoint_url or "aws",
    }
