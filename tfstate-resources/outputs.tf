output "s3_bucket_name" {
  description = "The name of the S3 bucket that holds the tfstate"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table responsible for the tfstate lock"
  value       = aws_dynamodb_table.terraform_locks.id
}