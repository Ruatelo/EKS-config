output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = aws_eks_cluster.eks.endpoint
}

output "cluster_certificate_authority" {
  description = "Certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.eks.certificate_authority[0].data
  sensitive   = true
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch Log Group for EKS audit logs"
  value       = aws_cloudwatch_log_group.eks_audit_logs.name
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig for connecting to the cluster"
  value       = "aws eks update-kubeconfig --name eks-attacks-lab --region us-east-1"
}

output "node_group_name" {
  description = "Name of the EKS node group"
  value       = aws_eks_node_group.standard_workers.node_group_name
}
