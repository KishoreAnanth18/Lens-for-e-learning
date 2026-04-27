# Local Development Guide

Uses LocalStack to simulate S3, DynamoDB, Cognito, Lambda, and API Gateway locally — no AWS account or costs needed.

## Prerequisites

- Docker Desktop running

## Start LocalStack

```bash
docker compose up -d
```

LocalStack automatically creates all required resources on startup (S3 bucket, DynamoDB table, Cognito User Pool) via `scripts/localstack-init/01-create-resources.sh`.

## Configure the backend

```bash
cd backend
cp .env.example .env
```

`USE_LOCALSTACK=True` and `USE_MOCK_AUTH=True` are already set in `.env.example` — no further configuration needed for local dev.

## Start the backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

## Verify connectivity

```bash
curl http://localhost:8000/api/v1/health/aws
```

Expected:
```json
{"status": "healthy", "services": {"dynamodb": "ok", "s3": "ok"}, "endpoint": "http://localhost:4566"}
```

## Inspect persisted data

Scan the LocalStack DynamoDB table:
```powershell
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name lens-elearning-local --region us-east-1
```

List LocalStack S3 objects:
```powershell
aws --endpoint-url=http://localhost:4566 s3 ls s3://lens-elearning-images --recursive
```

## Stop LocalStack

```bash
docker compose down
```

## Running tests

```bash
cd backend
pytest
```

## Troubleshooting

**LocalStack not ready** — wait a few seconds after `docker compose up -d`, then retry. Check logs with:
```bash
docker compose logs localstack
```

**Services show errors on health check** — the init script may still be running. Wait 10-15 seconds and retry.
