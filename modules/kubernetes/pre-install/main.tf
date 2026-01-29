# Configure Kubernetes provider
/*provider "kubernetes" {
  host                   = "https://${var.cluster_endpoint}"
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    host                   = "https://${var.cluster_endpoint}"
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}*/

# Create LogScale namespace
resource "kubernetes_namespace" "logscale" {
  metadata {
    name = var.logscale_cluster_k8s_namespace_name
  }
}

# Google Managed Certificate for external GCE ingress
resource "kubernetes_manifest" "google_managed_certificate" {
  manifest = {
    "apiVersion" = "networking.gke.io/v1"
    "kind"       = "ManagedCertificate"
    "metadata" = {
      "name"      = "${var.logscale_cluster_name}-google-managed-certificate"
      "namespace" = var.logscale_cluster_k8s_namespace_name
    }
    "spec" = {
      "domains" = [var.public_url]
    }
  }

  depends_on = [kubernetes_namespace.logscale]
}

# BackendConfig for external services
resource "kubernetes_manifest" "logscale_backend_config" {
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind"       = "BackendConfig"
    "metadata" = {
      "name"      = "${var.logscale_cluster_name}-healthcheck-config"
      "namespace" = var.logscale_cluster_k8s_namespace_name
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec"   = 15
        "timeoutSec"         = 10
        "healthyThreshold"   = 1
        "requestPath"        = "/api/v1/status"
        "type"               = "HTTPS"
        "unhealthyThreshold" = 3
      }
    }
  }

  depends_on = [kubernetes_namespace.logscale]
}

# BackendConfig for internal ingest service (advanced type only)
resource "kubernetes_manifest" "logscale_internal_ingest_backend_config" {
  count = var.logscale_cluster_type == "advanced" ? 1 : 0
  
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind"       = "BackendConfig"
    "metadata" = {
      "name"      = "${var.logscale_cluster_name}-ingest-healthcheck-config"
      "namespace" = var.logscale_cluster_k8s_namespace_name
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec"   = 15
        "timeoutSec"         = 10
        "healthyThreshold"   = 1
        "requestPath"        = "/api/v1/status"
        "type"               = "HTTPS"
        "unhealthyThreshold" = 3
      }
    }
  }

  depends_on = [kubernetes_namespace.logscale]
}

# Create a random key for encrypting data in bucket storage
resource "random_password" "gcp_storage_encryption_password" {
  length  = 64
  special = false
}

# Create an encryption key for the data stored in GCP
resource "kubernetes_secret" "gcp_storage_encryption_key" {
  metadata {
    name      = "${var.logscale_cluster_name}-gcp-storage-encryption-key"
    namespace = var.logscale_cluster_k8s_namespace_name
  }
  data = {
    gcp-storage-encryption-key = random_password.gcp_storage_encryption_password.result
  }
  
  depends_on = [kubernetes_namespace.logscale]
}

# Create a random password for static admin user
/*resource "random_password" "static_admin_password" {
  length  = 18
  special = false
}

# Create a secret for the admin user
resource "kubernetes_secret" "static_user_logins" {
  metadata {
    name      = "${var.logscale_cluster_name}-static-users"
    namespace = var.logscale_cluster_k8s_namespace_name
  }
  data = {
    users = "admin:${random_password.static_admin_password.result}"
  }
  
  depends_on = [kubernetes_namespace.logscale]
}*/

# ==========================================
# GCP SERVICE AND INGRESS RESOURCES
# ==========================================

locals {
  # GCP service annotations for external services
  gcp_service_annotations = {
    "cloud.google.com/backend-config" = "{\"default\": \"${var.logscale_cluster_name}-healthcheck-config\"}"
    "cloud.google.com/app-protocols"  = "{\"logscale-port\":\"HTTPS\"}"
  }

  # GCP service annotations for internal ingest service
  gcp_internal_service_annotations = {
    "cloud.google.com/backend-config" = "{\"default\": \"${var.logscale_cluster_name}-ingest-healthcheck-config\"}"
    "cloud.google.com/app-protocols"  = "{\"logscale-port\":\"HTTPS\"}"
    "cloud.google.com/neg"            = "{\"ingress\": true}"
  }

  # GCP external ingress annotations
  gcp_ingress_annotations = {
    "kubernetes.io/ingress.class"                 = "gce"
    "kubernetes.io/ingress.global-static-ip-name" = var.gcp_static_ip_name
    "kubernetes.io/ingress.allow-http"            = "false"
    "networking.gke.io/managed-certificates"      = "${var.logscale_cluster_name}-google-managed-certificate"
  }

  # GCP internal ingress annotations
  gcp_internal_ingress_annotations = {
    "kubernetes.io/ingress.class"      = "gce-internal"
    "kubernetes.io/ingress.allow-http" = "false"
    "cert-manager.io/issuer"           = var.humio_cluster_instance_name
  }
}

# NodePort service for GCP external ingress
resource "kubernetes_service" "logscale_nodeport" {
  metadata {
    name        = "${var.logscale_cluster_name}-nodeport"
    namespace   = var.logscale_cluster_k8s_namespace_name
    annotations = local.gcp_service_annotations
  }

  spec {
    type     = "NodePort"
    selector = {
      "app.kubernetes.io/name" = "humio"
    }
    port {
      port        = 8080
      target_port = 8080
      name        = "logscale-port"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"]
    ]
  }

  depends_on = [kubernetes_namespace.logscale]
}

# GCP internal ingest service (for advanced cluster type only)
resource "kubernetes_service" "logscale_gcp_internal_ingest_nodeport" {
  count = var.logscale_cluster_type == "advanced" ? 1 : 0
  
  metadata {
    name        = "${var.logscale_cluster_name}-nodeport-ingest"
    namespace   = var.logscale_cluster_k8s_namespace_name
    annotations = local.gcp_internal_service_annotations
  }

  spec {
    type     = "NodePort"
    selector = {
      "humio.com/node-pool" = "${var.logscale_cluster_name}-ingest-only"
    }
    port {
      port        = 8080
      target_port = 8080
      name        = "logscale-port"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"]
    ]
  }

  depends_on = [kubernetes_namespace.logscale]
}

# GKE EXTERNAL INGRESS (Service-based routing)
resource "kubernetes_ingress_v1" "logscale_gke_ingress" {
  metadata {
    name        = "${var.logscale_cluster_name}-ui"
    namespace   = var.logscale_cluster_k8s_namespace_name
    annotations = local.gcp_ingress_annotations
  }
  
  spec {
    # No ingress_class_name for GCP (uses annotations)
    
    # No TLS block (uses Google-managed certificates)

    # Default backend - ALL traffic goes to primary service
    default_backend {
      service {
        name = kubernetes_service.logscale_nodeport.metadata[0].name
        port {
          number = 8080
        }
      }
    }

    # Service-based routing rule - ALL traffic to one service
    rule {
      host = var.public_url
      
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.logscale_nodeport.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.logscale, kubernetes_service.logscale_nodeport]
}

# GCP INTERNAL INGRESS (For advanced type)
resource "kubernetes_ingress_v1" "logscale_gcp_internal_ingress" {
  count = var.logscale_cluster_type == "advanced" ? 1 : 0
  
  metadata {
    name        = "${var.logscale_cluster_name}-ingest-ingress"
    namespace   = var.logscale_cluster_k8s_namespace_name
    annotations = local.gcp_internal_ingress_annotations
  }
  
  spec {
    # No ingress_class_name (uses gce-internal annotation)
    
    # TLS configuration - cert-manager will auto-provision based on annotations
    tls {
      hosts = [
        "${var.logscale_cluster_name}-advanced.${var.logscale_cluster_k8s_namespace_name}",
        "${var.logscale_cluster_name}-advanced-headless.${var.logscale_cluster_k8s_namespace_name}"
      ]
      secret_name = "${var.logscale_cluster_name}-advanced"
    }

    # Default backend - internal ingest traffic
    default_backend {
      service {
        name = kubernetes_service.logscale_gcp_internal_ingest_nodeport[0].metadata[0].name
        port {
          number = 8080
        }
      }
    }

    # Internal service-based routing rule
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.logscale_gcp_internal_ingest_nodeport[0].metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.logscale, kubernetes_service.logscale_gcp_internal_ingest_nodeport]
}