variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "lens-elearning-prod"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for image storage"
  type        = string
  default     = "lens-elearning-images"
}
