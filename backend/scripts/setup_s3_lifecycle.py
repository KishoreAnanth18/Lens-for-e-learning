"""
Configure S3 lifecycle policies for the lens-elearning-images bucket.

Rules:
  - Delete objects under temp/ prefix after 1 day
  - Transition objects under scans/ prefix to Intelligent-Tiering after 30 days

Usage:
    python backend/scripts/setup_s3_lifecycle.py [--bucket BUCKET_NAME]
"""

import argparse
import sys

import boto3
from botocore.exceptions import ClientError


LIFECYCLE_CONFIGURATION = {
    "Rules": [
        {
            "ID": "delete-temp-after-1-day",
            "Status": "Enabled",
            "Filter": {"Prefix": "temp/"},
            "Expiration": {"Days": 1},
        },
        {
            "ID": "transition-scans-to-intelligent-tiering",
            "Status": "Enabled",
            "Filter": {"Prefix": "scans/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "INTELLIGENT_TIERING",
                }
            ],
        },
    ]
}


def apply_lifecycle(bucket_name: str, endpoint_url: str | None = None) -> None:
    kwargs = {}
    if endpoint_url:
        kwargs["endpoint_url"] = endpoint_url

    s3 = boto3.client("s3", **kwargs)

    try:
        s3.put_bucket_lifecycle_configuration(
            Bucket=bucket_name,
            LifecycleConfiguration=LIFECYCLE_CONFIGURATION,
        )
        print(f"Lifecycle configuration applied to bucket '{bucket_name}'.")
        for rule in LIFECYCLE_CONFIGURATION["Rules"]:
            print(f"  - Rule '{rule['ID']}': {rule['Status']}")
    except ClientError as exc:
        print(f"ERROR: Failed to apply lifecycle configuration: {exc}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Configure S3 lifecycle policies.")
    parser.add_argument(
        "--bucket",
        default="lens-elearning-images",
        help="S3 bucket name (default: lens-elearning-images)",
    )
    parser.add_argument(
        "--endpoint-url",
        default=None,
        help="Custom endpoint URL (e.g. http://localhost:4566 for LocalStack)",
    )
    args = parser.parse_args()
    apply_lifecycle(args.bucket, args.endpoint_url)


if __name__ == "__main__":
    main()
