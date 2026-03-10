terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# DynamoDB Table
resource "aws_dynamodb_table" "lens_elearning" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  tags = {
    Name        = "lens-elearning-prod"
    Environment = var.environment
    Project     = "lens-elearning"
  }
}

# S3 Bucket for Image Storage
resource "aws_s3_bucket" "images" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "lens-elearning-images"
    Environment = var.environment
    Project     = "lens-elearning"
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Disabled"
  }
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "delete-temp-uploads"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 1
    }
  }

  rule {
    id     = "transition-to-intelligent-tiering"
    status = "Enabled"

    filter {
      prefix = "scans/"
    }

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# S3 Bucket CORS Configuration
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "lens-elearning-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = {
    Name        = "lens-elearning-users"
    Environment = var.environment
    Project     = "lens-elearning"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "lens-elearning-mobile"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = ["lenselearning://callback"]
  logout_urls                          = ["lenselearning://logout"]

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 24
  id_token_validity      = 24
  refresh_token_validity = 30
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution" {
  name = "lens-elearning-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "lens-elearning-lambda-execution"
    Environment = var.environment
    Project     = "lens-elearning"
  }
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lens-elearning-lambda-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.lens_elearning.arn,
          "${aws_dynamodb_table.lens_elearning.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:*:function:lens-elearning-*"
      }
    ]
  })
}
