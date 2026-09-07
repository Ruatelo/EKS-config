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
