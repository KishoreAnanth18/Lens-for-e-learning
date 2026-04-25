"""FastAPI application entry point"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.auth.router import router as auth_router
from app.core.config import settings

app = FastAPI(
    title="Lens for E-Learning API",
    description="Backend API for Lens for E-Learning MVP",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/api/v1")


@app.get("/api/v1/health")
async def health_check():
    """Health check endpoint"""
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

    # DynamoDB
    try:
        ddb = get_dynamodb_resource()
        table = ddb.Table(settings.DYNAMODB_TABLE_NAME)
        table.load()
        results["dynamodb"] = "ok"
    except Exception as exc:
        results["dynamodb"] = f"error: {exc}"

    # S3
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
