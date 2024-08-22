variable "region" {
  default     = "us-east-1"
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "The EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "The EKS cluster version"
  type        = string
}

variable "vpc_name" {
  description = "The VPC name which the resources will live"
  type        = string
}

variable "bastion_security_group_name" {
  description = "The security group name of the EC2 bastion"
  type        = string
}

variable "rds_security_group_name" {
  description = "The security group name of the RDS database"
  type        = string
}

variable "efs_security_group_name" {
  description = "The security group name of the EFS filesystem"
  type        = string
}

variable "ec2_instance_type" {
  description = "The instance type of the bastion"
  type        = string
}

variable "eks_instance_type" {
  description = "The instance type of the EKS instances"
  type        = string
}


variable "ec2_bastion_name" {
  description = "The name of the bastion instance"
  type        = string
}

variable "db_name" {
  description = "The name of the RDS database"
  type        = string
}

variable "efs_name" {
  description = "The name of the EFS filesystem"
  type        = string
}

variable "db_instance_class" {
  description = "The instance class of the RDS db"
  type        = string
}

variable "db_user_name" {
  description = "The rds mysql username"
  sensitive   = true
  type        = string
}

variable "db_password" {
  description = "The rds mysql password"
  sensitive   = true
  type        = string
}
