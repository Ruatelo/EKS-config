# ─── Prod namespace ──────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "prod" {
  metadata {
    name = "prod"
    labels = {
      environment = "production"
      team        = "platform-engineering"
    }
  }
}

# ─── Overprivileged service account (the misconfiguration) ───────────────────

resource "kubernetes_service_account_v1" "prod_admin" {
  metadata {
    name      = "prod-admin-sa"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    labels = {
      app         = "payment-processor"
      environment = "production"
    }
  }
}

resource "kubernetes_cluster_role_binding_v1" "prod_admin" {
  metadata {
    name = "prod-admin-binding"
    labels = {
      app = "payment-processor"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.prod_admin.metadata[0].name
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
  }
}

# ─── Vulnerable app (default namespace) ──────────────────────────────────────

resource "kubernetes_deployment_v1" "health_dashboard" {
  metadata {
    name      = "health-dashboard"
    namespace = "default"
    labels = {
      app = "health-dashboard"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "health-dashboard"
      }
    }
    template {
      metadata {
        labels = {
          app = "health-dashboard"
        }
      }
      spec {
        node_selector = {
          scenario1 = "target"
        }
        container {
          name  = "dashboard"
          image = "${aws_ecr_repository.vulnerable_app.repository_url}:latest"
          port {
            container_port = 8080
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.docker_build_push,
    kubernetes_labels.target_node
  ]
}

resource "kubernetes_service_v1" "health_dashboard" {
  metadata {
    name      = "health-dashboard"
    namespace = "default"
    labels = {
      app = "health-dashboard"
    }
  }

  spec {
    type                    = "LoadBalancer"
    load_balancer_source_ranges = [var.allowed_ip]
    selector = {
      app = "health-dashboard"
    }
    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }
}

# ─── Prod workload (target pod for impersonation) ────────────────────────────

resource "kubernetes_pod_v1" "payment_processor" {
  metadata {
    name      = "payment-processor"
    namespace = kubernetes_namespace_v1.prod.metadata[0].name
    labels = {
      app         = "payment-processor"
      environment = "production"
    }
  }

  spec {
    service_account_name = kubernetes_service_account_v1.prod_admin.metadata[0].name
    node_selector = {
      scenario1 = "target"
    }
    container {
      name    = "processor"
      image   = "busybox:1.36"
      command = ["sleep", "infinity"]
      resources {
        requests = {
          cpu    = "50m"
          memory = "32Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "64Mi"
        }
      }
    }
  }

  depends_on = [kubernetes_labels.target_node]
}
