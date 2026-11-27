output "alb_dns_name" {
  description = "Public DNS name for the TaskFlow application load balancer."
  value       = aws_lb.taskflow.dns_name
}

output "backend_ecr_repository_url" {
  description = "ECR repository URL for the backend image."
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repository_url" {
  description = "ECR repository URL for the frontend image."
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.taskflow.name
}

output "mongo_uri_parameter_name" {
  description = "SSM parameter containing the MongoDB connection string."
  value       = aws_ssm_parameter.mongo_uri.name
}

output "github_cd_role_arn" {
  description = "IAM role assumed by GitHub Actions through OIDC."
  value       = aws_iam_role.github_cd.arn
}
