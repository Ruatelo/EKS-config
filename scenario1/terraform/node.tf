# Find EKS worker node instances
data "aws_instances" "eks_nodes" {
  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# Get details for the target node (first instance)
data "aws_instance" "target_node" {
  instance_id = data.aws_instances.eks_nodes.ids[0]
}

# ─── Node label ──────────────────────────────────────────────────────────────
# Both pods use nodeSelector: scenario1=target to guarantee co-location

resource "kubernetes_labels" "target_node" {
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = data.aws_instance.target_node.private_dns
  }
  labels = {
    "scenario1" = "target"
  }
}

# ─── EC2 tags (attacker discovers these during recon via IMDS + describe-tags)

resource "aws_ec2_tag" "environment" {
  resource_id = data.aws_instances.eks_nodes.ids[0]
  key         = "Environment"
  value       = "production"
}

resource "aws_ec2_tag" "namespaces" {
  resource_id = data.aws_instances.eks_nodes.ids[0]
  key         = "Namespaces"
  value       = "default,prod"
}

resource "aws_ec2_tag" "team" {
  resource_id = data.aws_instances.eks_nodes.ids[0]
  key         = "Team"
  value       = "platform-engineering"
}

resource "aws_ec2_tag" "cost_center" {
  resource_id = data.aws_instances.eks_nodes.ids[0]
  key         = "CostCenter"
  value       = "engineering-prod"
}
