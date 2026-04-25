"""Application configuration"""

from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings"""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

    # LocalStack
    USE_LOCALSTACK: bool = False
    LOCALSTACK_ENDPOINT: str = "http://localhost:4566"

    # AWS Configuration
    AWS_REGION: str = "us-east-1"
    AWS_ACCOUNT_ID: str = "000000000000"
    AWS_ACCESS_KEY_ID: str = "test"
    AWS_SECRET_ACCESS_KEY: str = "test"

    # Storage
    S3_BUCKET_NAME: str = "lens-elearning-images"
    DYNAMODB_TABLE_NAME: str = "lens-elearning-local"

    # Cognito - not used in local dev (USE_MOCK_AUTH=True bypasses Cognito)
    USE_MOCK_AUTH: bool = False
    COGNITO_USER_POOL_ID: str = ""
    COGNITO_CLIENT_ID: str = ""
    COGNITO_CLIENT_SECRET: str = ""

    # Lambda Functions
    NLP_LAMBDA_NAME: str = "lens-elearning-nlp-processor"
    SEARCH_LAMBDA_NAME: str = "lens-elearning-search-processor"

    # External APIs
    YOUTUBE_API_KEY: str = ""
    GOOGLE_SEARCH_API_KEY: str = ""
    GOOGLE_SEARCH_ENGINE_ID: str = ""

    # Application Settings
    JWT_SECRET_KEY: str = "change-this-in-production"
    JWT_ALGORITHM: str = "HS256"
    TOKEN_EXPIRE_DAYS: int = 30

    # Environment
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"

    @property
    def aws_endpoint_url(self) -> Optional[str]:
        """Returns LocalStack endpoint when enabled, None for real AWS."""
        return self.LOCALSTACK_ENDPOINT if self.USE_LOCALSTACK else None

    @property
    def boto3_kwargs(self) -> dict:
        """Common kwargs for all boto3 clients/resources."""
        kwargs = {"region_name": self.AWS_REGION}
        if self.USE_LOCALSTACK:
            kwargs["endpoint_url"] = self.LOCALSTACK_ENDPOINT
            kwargs["aws_access_key_id"] = self.AWS_ACCESS_KEY_ID
            kwargs["aws_secret_access_key"] = self.AWS_SECRET_ACCESS_KEY
        return kwargs


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
