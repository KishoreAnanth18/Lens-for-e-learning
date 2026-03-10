"""Application configuration"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings"""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

    # AWS Configuration
    AWS_REGION: str = "us-east-1"
    AWS_ACCOUNT_ID: str = ""
    S3_BUCKET_NAME: str = "lens-elearning-images"
    DYNAMODB_TABLE_NAME: str = "lens-elearning-prod"

    # Cognito Configuration
    COGNITO_USER_POOL_ID: str = ""
    COGNITO_CLIENT_ID: str = ""
    COGNITO_CLIENT_SECRET: str = ""

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


settings = Settings()
