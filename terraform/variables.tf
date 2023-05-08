variable "region" {
  default     = "us-east-1"
  description = "AWS region"
}

variable "db_user_name" {
  description = "The rds mysql username"
  sensitive   = true
}

variable "db_password" {
  description = "The rds mysql password"
  sensitive   = true
}