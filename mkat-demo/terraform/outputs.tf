output "secure_irsa_role_arn" {
  description = "ARN of the securely-scoped IRSA role (StringEquals, specific SA)"
  value       = aws_iam_role.s3_reader_secure.arn
}

output "vulnerable_irsa_no_sub_role_arn" {
  description = "ARN of the vulnerable IRSA role (missing sub condition)"
  value       = aws_iam_role.s3_reader_vulnerable.arn
}

output "vulnerable_irsa_wildcard_role_arn" {
  description = "ARN of the vulnerable IRSA role (wildcard sub condition)"
  value       = aws_iam_role.s3_admin_wildcard.arn
}

output "pod_identity_role_arn" {
  description = "ARN of the Pod Identity role (specific SA)"
  value       = aws_iam_role.pod_identity_role.arn
}

output "pod_identity_wildcard_role_arn" {
  description = "ARN of the Pod Identity role (wildcard SA)"
  value       = aws_iam_role.pod_identity_wildcard_role.arn
}

output "demo_bucket_name" {
  description = "Name of the S3 bucket created for the demo"
  value       = aws_s3_bucket.mkat_demo_data.id
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig for connecting to the cluster"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
}
