output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.vulnerable_app.repository_url
}

output "app_url" {
  description = "Vulnerable app URL (may take a minute to resolve)"
  value       = "http://${kubernetes_service_v1.health_dashboard.status[0].load_balancer[0].ingress[0].hostname}"
}

output "target_node" {
  description = "Target node name (both pods are scheduled here)"
  value       = data.aws_instance.target_node.private_dns
}

output "target_instance_id" {
  description = "Target EC2 instance ID"
  value       = data.aws_instances.eks_nodes.ids[0]
}
