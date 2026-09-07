# ---------------------------------------------------------------------------
# Kubernetes Resources — Complete Infrastructure as Code
#
# Fully provisions the namespace, service accounts (with live IAM role ARNs),
# configmaps & secrets (with intentional test credentials), and deployments.
# Everything deploys in a single `terraform apply` with no extra scripts.
# ---------------------------------------------------------------------------

# ============================================================================
# 1. Namespace
# ============================================================================

resource "kubernetes_namespace_v1" "mkat_demo" {
  metadata {
    name = "mkat-demo"
    labels = {
      app     = "mkat-demo"
      purpose = "security-auditing"
    }
  }
}

# ============================================================================
# 2. Service Accounts (with dynamic IAM Role ARNs)
# ============================================================================

# --- Secure IRSA ---
resource "kubernetes_service_account_v1" "s3_reader_sa" {
  metadata {
    name      = "s3-reader-sa"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_reader_secure.arn
    }
    labels = {
      app       = "mkat-demo"
      component = "service-account"
      security  = "secure"
      mechanism = "irsa"
    }
  }
}

# --- Vulnerable IRSA (missing sub condition) ---
resource "kubernetes_service_account_v1" "s3_vulnerable_sa" {
  metadata {
    name      = "s3-vulnerable-sa"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_reader_vulnerable.arn
    }
    labels = {
      app       = "mkat-demo"
      component = "service-account"
      security  = "vulnerable"
      mechanism = "irsa"
    }
  }
}

# --- Vulnerable IRSA (wildcard sub condition) ---
resource "kubernetes_service_account_v1" "s3_wildcard_sa" {
  metadata {
    name      = "s3-wildcard-sa"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_admin_wildcard.arn
    }
    labels = {
      app       = "mkat-demo"
      component = "service-account"
      security  = "vulnerable"
      mechanism = "irsa"
    }
  }
}

# --- Secure Pod Identity ---
resource "kubernetes_service_account_v1" "dynamo_reader_sa" {
  metadata {
    name      = "dynamo-reader-sa"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "mkat-demo"
      component = "service-account"
      security  = "secure"
      mechanism = "pod-identity"
    }
  }
}

# --- Pod Identity (default SA demo companion) ---
resource "kubernetes_service_account_v1" "secrets_manager_sa" {
  metadata {
    name      = "secrets-manager-sa"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "mkat-demo"
      component = "service-account"
      security  = "vulnerable"
      mechanism = "pod-identity"
    }
  }
}

# ============================================================================
# 3. ConfigMaps & Secrets (Hardcoded Credentials for MKAT find-secrets)
# ============================================================================

resource "kubernetes_config_map_v1" "legacy_app_config" {
  metadata {
    name      = "legacy-app-config"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "mkat-demo"
      component = "configmap"
      security  = "vulnerable"
    }
  }

  data = {
    AWS_ACCESS_KEY_ID     = "AKIAIOSFODNN7EXAMPLE"
    AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    AWS_DEFAULT_REGION    = "us-east-1"
    APP_NAME              = "legacy-data-processor"
  }
}

resource "kubernetes_config_map_v1" "backup_cron_config" {
  metadata {
    name      = "backup-cron-config"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "mkat-demo"
      component = "configmap"
      security  = "vulnerable"
    }
  }

  data = {
    BACKUP_BUCKET     = "company-backups-prod"
    BACKUP_AWS_KEY    = "AKIAI44QH8DHBEXAMPLE"
    BACKUP_AWS_SECRET = "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY"
    BACKUP_SCHEDULE   = "0 2 * * *"
  }
}

resource "kubernetes_secret_v1" "database_credentials" {
  metadata {
    name      = "database-credentials"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "mkat-demo"
      component = "secret"
      security  = "vulnerable"
    }
  }

  type = "Opaque"

  data = {
    db_host               = "prod-db.cluster-abc123.us-east-1.rds.amazonaws.com"
    db_user               = "admin"
    db_password           = "SuperS3cretP@ssw0rd!"
    aws_access_key_id     = "AKIAYRJXG5BB6EXAMPLE"
    aws_secret_access_key = "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"
  }
}

# ============================================================================
# 4. Deployments
# ============================================================================

# --- Deployment 1: IRSA Secure ---
resource "kubernetes_deployment_v1" "s3_reader" {
  metadata {
    name      = "s3-reader"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "s3-reader"
      component = "irsa-secure"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "s3-reader"
      }
    }
    template {
      metadata {
        labels = {
          app       = "s3-reader"
          component = "irsa-secure"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.s3_reader_sa.metadata[0].name
        container {
          name  = "s3-reader"
          image = "nginx:alpine"
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# --- Deployment 2: IRSA Vulnerable (missing sub condition) ---
resource "kubernetes_deployment_v1" "s3_vulnerable_app" {
  metadata {
    name      = "s3-vulnerable-app"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "s3-vulnerable-app"
      component = "irsa-vulnerable"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "s3-vulnerable-app"
      }
    }
    template {
      metadata {
        labels = {
          app       = "s3-vulnerable-app"
          component = "irsa-vulnerable"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.s3_vulnerable_sa.metadata[0].name
        container {
          name  = "app"
          image = "nginx:alpine"
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# --- Deployment 3: IRSA Wildcard + Hardcoded Credentials ---
resource "kubernetes_deployment_v1" "data_processor" {
  metadata {
    name      = "data-processor"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "data-processor"
      component = "hardcoded-creds"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "data-processor"
      }
    }
    template {
      metadata {
        labels = {
          app       = "data-processor"
          component = "hardcoded-creds"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.s3_wildcard_sa.metadata[0].name
        container {
          name    = "processor"
          image   = "python:3.11-slim"
          command = ["python", "-c", "import time; time.sleep(3600)"]

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.legacy_app_config.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# --- Deployment 4: Pod Identity Secure ---
resource "kubernetes_deployment_v1" "dynamo_reader" {
  metadata {
    name      = "dynamo-reader"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "dynamo-reader"
      component = "pod-identity-secure"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "dynamo-reader"
      }
    }
    template {
      metadata {
        labels = {
          app       = "dynamo-reader"
          component = "pod-identity-secure"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.dynamo_reader_sa.metadata[0].name
        container {
          name    = "dynamo-reader"
          image   = "amazon/aws-cli:latest"
          command = ["sleep", "3600"]
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# --- Deployment 5: Pod Identity Overprivileged ---
resource "kubernetes_deployment_v1" "secrets_manager_app" {
  metadata {
    name      = "secrets-manager-app"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "secrets-manager-app"
      component = "pod-identity-wildcard"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "secrets-manager-app"
      }
    }
    template {
      metadata {
        labels = {
          app       = "secrets-manager-app"
          component = "pod-identity-wildcard"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.secrets_manager_sa.metadata[0].name
        container {
          name  = "app"
          image = "nginx:alpine"
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# --- Deployment 6: Backup Job (default SA + hardcoded credentials) ---
resource "kubernetes_deployment_v1" "backup_job" {
  metadata {
    name      = "backup-job"
    namespace = kubernetes_namespace_v1.mkat_demo.metadata[0].name
    labels = {
      app       = "backup-job"
      component = "hardcoded-creds"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "backup-job"
      }
    }
    template {
      metadata {
        labels = {
          app       = "backup-job"
          component = "hardcoded-creds"
        }
      }
      spec {
        container {
          name    = "backup"
          image   = "alpine:latest"
          command = ["sh", "-c", "while true; do echo 'backup running'; sleep 3600; done"]

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.backup_cron_config.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.database_credentials.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# ============================================================================
# 5. Sync rendered YAML manifest to disk (Reference copy)
# ============================================================================
resource "local_file" "service_accounts_manifest" {
  filename = "${path.module}/../k8s-manifests/01-service-accounts.yaml"
  content  = <<-EOT
# -------------------------------------------------------------------
# Service Accounts for MKAT Demo (Auto-generated by Terraform)
# -------------------------------------------------------------------

apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader-sa
  namespace: mkat-demo
  annotations:
    eks.amazonaws.com/role-arn: "${aws_iam_role.s3_reader_secure.arn}"
  labels:
    app: mkat-demo
    component: service-account
    security: secure
    mechanism: irsa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-vulnerable-sa
  namespace: mkat-demo
  annotations:
    eks.amazonaws.com/role-arn: "${aws_iam_role.s3_reader_vulnerable.arn}"
  labels:
    app: mkat-demo
    component: service-account
    security: vulnerable
    mechanism: irsa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-wildcard-sa
  namespace: mkat-demo
  annotations:
    eks.amazonaws.com/role-arn: "${aws_iam_role.s3_admin_wildcard.arn}"
  labels:
    app: mkat-demo
    component: service-account
    security: vulnerable
    mechanism: irsa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dynamo-reader-sa
  namespace: mkat-demo
  labels:
    app: mkat-demo
    component: service-account
    security: secure
    mechanism: pod-identity
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secrets-manager-sa
  namespace: mkat-demo
  labels:
    app: mkat-demo
    component: service-account
    security: vulnerable
    mechanism: pod-identity
EOT
}
