output "cluster_endpoint" {
  description = "The endpoint for the EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "The endpoint of the RDS database"
  value       = aws_db_instance.rds_wp.endpoint
}

output "efs_endpoint" {
  description = "The endpoint of the efs filesystem"
  value       = aws_efs_file_system.efs.id
}