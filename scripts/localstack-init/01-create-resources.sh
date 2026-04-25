#!/bin/bash
# LocalStack initialization script - runs automatically on startup

set -e

echo "=== Initializing LocalStack resources ==="

ENDPOINT="http://localhost:4566"
REGION="us-east-1"
AWS_CMD="aws --endpoint-url=$ENDPOINT --region=$REGION"

# ── S3 Bucket ──────────────────────────────────────────────────────────────
echo "Creating S3 bucket..."
$AWS_CMD s3 mb s3://lens-elearning-images 2>/dev/null || echo "S3 bucket already exists"

$AWS_CMD s3api put-bucket-cors \
  --bucket lens-elearning-images \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET","PUT","POST","DELETE"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag"]
    }]
  }'

echo "✓ S3 bucket ready: lens-elearning-images"

# ── DynamoDB Table ─────────────────────────────────────────────────────────
echo "Creating DynamoDB table..."
$AWS_CMD dynamodb create-table \
  --table-name lens-elearning-local \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
    AttributeName=GSI1PK,AttributeType=S \
    AttributeName=GSI1SK,AttributeType=S \
  --key-schema \
    AttributeName=PK,KeyType=HASH \
    AttributeName=SK,KeyType=RANGE \
  --global-secondary-indexes '[
    {
      "IndexName": "GSI1",
      "KeySchema": [
        {"AttributeName":"GSI1PK","KeyType":"HASH"},
        {"AttributeName":"GSI1SK","KeyType":"RANGE"}
      ],
      "Projection": {"ProjectionType":"ALL"}
    }
  ]' \
  --billing-mode PAY_PER_REQUEST 2>/dev/null || echo "DynamoDB table already exists"

echo "✓ DynamoDB table ready: lens-elearning-local"

echo ""
echo "=== LocalStack initialization complete ==="
echo "  S3 Bucket:      lens-elearning-images"
echo "  DynamoDB Table: lens-elearning-local"
echo ""
