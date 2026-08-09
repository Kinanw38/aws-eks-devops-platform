output "cluster_name" {
  description = "שם אשכול ה-EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "כתובת ה-API Server של ה-EKS"
  value       = module.eks.cluster_endpoint
}

output "aws_region" {
  description = "אזור AWS שבו הוקם ה-Cluster"
  value       = var.aws_region
}

output "vpc_id" {
  description = "מזהה ה-VPC שיצרנו"
  value       = module.vpc.vpc_id
}