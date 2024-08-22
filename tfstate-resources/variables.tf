variable "region" {
  default     = "us-east-1"
  description = "AWS region"
  type        = string
}

variable "s3_bucket_name" {
  default     = "bucket-terraform-state"
  description = "The name of the tfstate S3 bucket"
  type        = string
}

variable "dynamodb_table_name" {
  default     = "table-terraform-state-locks"
  description = "The name of the dynamodb table for state locking"
  type        = string
}
