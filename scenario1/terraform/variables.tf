variable "region" {
  type        = string
  description = "AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
  default     = "eks-attacks-lab"
}

variable "allowed_ip" {
  type        = string
  description = "Your public IP in CIDR notation (e.g., 203.0.113.42/32) — only this IP can reach the vulnerable app"
}
