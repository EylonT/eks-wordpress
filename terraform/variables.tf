variable "region" {
  default = "us-east-1"
  description = "AWS region"
}

variable "key_pair" {
  description = "key pair for the ec2 instances"
  sensitive   = true
}

variable "db_user_name" {
  description = "the rds mysql username"
  sensitive   = true
}

variable "db_password" {
  description = "the rds mysql password"
  sensitive   = true
}