variable "region" {
  default     = "us-east-1"
  description = "AWS region"
}

variable "cluster_name" {
  description = "The EKS cluster name"
}

variable "cluster_version" {
  description = "The EKS cluster version"
}

variable "vpc_name" {
  description = "The VPC name which the resources will live"
}

variable "bastion_security_group_name" {
  description = "The security group name of the EC2 bastion"
}

variable "rds_security_group_name" {
  description = "The security group name of the RDS database"
}

variable "efs_security_group_name" {
  description = "The security group name of the EFS filesystem"
}

variable "ec2_instance_type" {
  description = "The instance type of the bastion"
}

variable "eks_instance_type" {
  description = "The instance type of the EKS instances"
}


variable "ec2_bastion_name" {
  description = "The name of the bastion instance"
}

variable "db_name" {
  description = "The name of the RDS database"
}

variable "efs_name" {
  description = "The name of the EFS filesystem"
}

variable "db_instance_class" {
  description = "The instance class of the RDS db"
}

variable "db_user_name" {
  description = "The rds mysql username"
  sensitive   = true
}

variable "db_password" {
  description = "The rds mysql password"
  sensitive   = true
}