"""AWS client factory - routes to LocalStack or real AWS based on config."""

from functools import lru_cache

import boto3

from app.core.config import settings


@lru_cache
def get_dynamodb_resource():
    return boto3.resource("dynamodb", **settings.boto3_kwargs)


@lru_cache
def get_s3_client():
    return boto3.client("s3", **settings.boto3_kwargs)


@lru_cache
def get_cognito_client():
    return boto3.client("cognito-idp", **settings.boto3_kwargs)


@lru_cache
def get_lambda_client():
    return boto3.client("lambda", **settings.boto3_kwargs)
