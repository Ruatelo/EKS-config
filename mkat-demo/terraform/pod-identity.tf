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
# MKAT's `eks find-role-relationships` checks Pod Identity associations for:
#   1. Scoped association (specific SA name) — secure
#   2. Association on `default` SA — overprivileged, any unscoped pod gets creds
# ---------------------------------------------------------------------------

# ============================================================================
# ROLE 1 — SECURE: Pod Identity with specific service account
#
# This role trusts the pods.eks.amazonaws.com service principal with
# sts:AssumeRole + sts:TagSession (required by EKS Pod Identity).
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
          "sts:TagSession"
        ]
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
# ROLE 2 — VULNERABLE: Pod Identity with overly broad service account
#
# This association maps to the `default` service account in the mkat-demo
# namespace. Every pod that does not explicitly set a serviceAccountName
# runs as `default` — meaning any unscoped workload in the namespace
# automatically gets SecretsManager read/write access.
#
# This is a common misconfiguration: teams associate a powerful IAM role
# with the `default` SA instead of creating a dedicated SA for the specific
# workload that needs it.
#
# MKAT will flag this as: "Pod Identity association on the default service
# account grants IAM access to all pods without an explicit SA"
# ============================================================================

resource "aws_iam_role" "pod_identity_wildcard_role" {
  name = "mkat-demo-pod-identity-overprivileged"

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
          "sts:TagSession"
        ]
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

# VULNERABLE association — maps to the `default` service account.
# Any pod without an explicit serviceAccountName gets this role.
resource "aws_eks_pod_identity_association" "overprivileged" {
  cluster_name    = var.cluster_name
  namespace       = "mkat-demo"
  service_account = "default"
  role_arn        = aws_iam_role.pod_identity_wildcard_role.arn

  tags = {
    Project  = "eks-attacks-lab"
    Demo     = "mkat"
    Security = "vulnerable"
  }
}

