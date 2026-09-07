# ---------------------------------------------------------------------------
# IRSA (IAM Roles for Service Accounts) — Secure and Vulnerable Configurations
#
# MKAT's `eks audit-iam-access` command inspects IAM role trust policies
# associated with Kubernetes service accounts via OIDC federation. It flags:
#   1. Trust policies missing the `sub` condition (any pod can assume the role)
#   2. Trust policies using StringLike with wildcard `sub` (too broad)
#   3. Properly scoped trust policies (StringEquals + specific SA) as secure
# ---------------------------------------------------------------------------

# --- OIDC Provider (required for IRSA) --------------------------------------
# The base cluster (initial-lab-deploy-trfm) creates the EKS cluster but does
# NOT create an IAM OIDC provider. IRSA requires one to federate Kubernetes
# service account tokens with AWS IAM via sts:AssumeRoleWithWebIdentity.

data "tls_certificate" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Project     = "eks-attacks-lab"
    Environment = "demo"
    ManagedBy   = "terraform"
    Demo        = "mkat"
  }
}

locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  oidc_issuer       = trimprefix(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://")
}

# --- EKS Pod Identity Agent (required for Pod Identity) ---------------------
# Pod Identity requires the eks-pod-identity-agent addon to be installed.
# This DaemonSet runs on each node and serves credentials via 169.254.170.23.

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = var.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "eks-attacks-lab"
    Environment = "demo"
    ManagedBy   = "terraform"
    Demo        = "mkat"
  }
}

# --- S3 Bucket (realistic target for IAM policies) -------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "mkat_demo_data" {
  bucket        = "mkat-demo-data-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Project     = "eks-attacks-lab"
    Environment = "demo"
    ManagedBy   = "terraform"
    Demo        = "mkat"
  }
}

# ============================================================================
# ROLE 1 — SECURE: Properly scoped IRSA role
#
# Trust policy uses StringEquals with the exact service account principal:
#   system:serviceaccount:mkat-demo:s3-reader-sa
#
# Only pods running as this specific SA in this specific namespace can assume
# the role. MKAT will report this as properly configured.
# ============================================================================

resource "aws_iam_role" "s3_reader_secure" {
  name = "mkat-demo-s3-reader-secure"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
            "${local.oidc_issuer}:sub" = "system:serviceaccount:mkat-demo:s3-reader-sa"
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

resource "aws_iam_role_policy_attachment" "s3_reader_secure_policy" {
  role       = aws_iam_role.s3_reader_secure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# ============================================================================
# ROLE 2 — VULNERABLE: Missing `sub` condition
#
# Trust policy only validates the OIDC issuer (aud) but does NOT restrict
# which service account can assume the role. This means ANY pod in the
# cluster — in ANY namespace — can assume this role by projecting a token
# from the OIDC provider.
#
# MKAT will flag this as: "Role can be assumed by any service account in the
# cluster (no sub condition in trust policy)"
# ============================================================================

resource "aws_iam_role" "s3_reader_vulnerable" {
  name = "mkat-demo-s3-reader-vulnerable"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # VULNERABILITY: Only checks audience, NOT which service account.
            # Any pod in the cluster can assume this role.
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
          # NOTE: No :sub condition — this is the misconfiguration MKAT detects.
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

resource "aws_iam_role_policy_attachment" "s3_reader_vulnerable_policy" {
  role       = aws_iam_role.s3_reader_vulnerable.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# ============================================================================
# ROLE 3 — VULNERABLE: Wildcard `sub` condition
#
# Trust policy uses StringLike with a wildcard pattern for the sub claim:
#   system:serviceaccount:mkat-demo:*
#
# This allows ANY service account in the mkat-demo namespace to assume the
# role — not just the intended one. An attacker who can create a new SA in
# the namespace (or compromise any pod) gets S3 Full Access.
#
# MKAT will flag this as: "Role can be assumed by any service account in
# namespace mkat-demo (wildcard sub condition)"
# ============================================================================

resource "aws_iam_role" "s3_admin_wildcard" {
  name = "mkat-demo-s3-admin-wildcard"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # VULNERABILITY: Wildcard allows any SA in the namespace.
            "${local.oidc_issuer}:sub" = "system:serviceaccount:mkat-demo:*"
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

resource "aws_iam_role_policy_attachment" "s3_admin_wildcard_policy" {
  role       = aws_iam_role.s3_admin_wildcard.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
