output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.lens_elearning.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.lens_elearning.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.images.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.images.arn
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}
