# ---------------------------------------------------------------------------
# EKS Pod Identity — Secure and Vulnerable Configurations
#
# Pod Identity is AWS's modern mechanism for granting IAM access to EKS pods.
# Instead of OIDC federation (IRSA), it uses the EKS Pod Identity Agent
# DaemonSet and a metadata-like endpoint (169.254.170.23) on each node.
#
# Associations are created via the EKS API (aws_eks_pod_identity_association)
# and map a specific namespace + service account to an IAM role.
#
# MKAT's `eks find-role-relationships` / audit checks Pod Identity associations:
#   1. Scoped association (specific SA name) — secure
#   2. Wildcard service account name (*) — any SA in the namespace can use it
# ---------------------------------------------------------------------------

# ============================================================================
# ROLE 1 — SECURE: Pod Identity with specific service account
#
# This role trusts the pods.eks.amazonaws.com service principal. The trust
# policy allows AssumeRole and AssumeRoleWithWebIdentity with a condition on
# the EKS cluster via sts:ExternalId.
#
# It is associated with a specific service account (dynamo-reader-sa) in the
# mkat-demo namespace. Only pods running as that SA get credentials.
# ============================================================================

resource "aws_iam_role" "pod_identity_role" {
  name = "mkat-demo-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:AssumeRoleWithWebIdentity"
        ]
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.cluster_name
          }
        }
      }
    ]
  })

  tags = {
    Project     = "eks-attacks-lab"
    Environment = "demo"
    ManagedBy   = "terraform"
    Demo        = "mkat"
    Security    = "secure"
  }
}

resource "aws_iam_role_policy_attachment" "pod_identity_dynamo_policy" {
  role       = aws_iam_role.pod_identity_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

# Secure association — scoped to a specific service account name.
resource "aws_eks_pod_identity_association" "dynamo_reader" {
  cluster_name    = var.cluster_name
  namespace       = "mkat-demo"
  service_account = "dynamo-reader-sa"
  role_arn        = aws_iam_role.pod_identity_role.arn

  tags = {
    Project  = "eks-attacks-lab"
    Demo     = "mkat"
    Security = "secure"
  }
}

# ============================================================================
# ROLE 2 — VULNERABLE: Pod Identity with wildcard service account
#
# This role trusts the pods.eks.amazonaws.com service principal with a condition
# on the EKS cluster via sts:ExternalId.
#
# However, the association uses a wildcard (*) for the service account name,
# meaning ANY service account in the mkat-demo namespace can assume this role.
#
# An attacker who can create a pod (or service account) in the namespace
# automatically gets SecretsManager read/write access.
#
# MKAT will flag this as: "Pod Identity association allows any service account
# in namespace mkat-demo to assume the role"
# ============================================================================

resource "aws_iam_role" "pod_identity_wildcard_role" {
  name = "mkat-demo-pod-identity-wildcard-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:AssumeRoleWithWebIdentity"
        ]
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.cluster_name
          }
        }
      }
    ]
  })

  tags = {
    Project     = "eks-attacks-lab"
    Environment = "demo"
    ManagedBy   = "terraform"
    Demo        = "mkat"
    Security    = "vulnerable"
  }
}

resource "aws_iam_role_policy_attachment" "pod_identity_wildcard_secrets_policy" {
  role       = aws_iam_role.pod_identity_wildcard_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# VULNERABLE association — wildcard service account.
# Any SA in the mkat-demo namespace can assume this role.
resource "aws_eks_pod_identity_association" "wildcard" {
  cluster_name    = var.cluster_name
  namespace       = "mkat-demo"
  service_account = "*"
  role_arn        = aws_iam_role.pod_identity_wildcard_role.arn

  tags = {
    Project  = "eks-attacks-lab"
    Demo     = "mkat"
    Security = "vulnerable"
  }
}
