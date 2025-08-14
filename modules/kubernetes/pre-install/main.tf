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

# Certificate for internal load balancer (advanced type only)
resource "kubernetes_manifest" "logscale_internal_ingest_cert" {
  count = var.logscale_cluster_type == "advanced" ? 1 : 0
  
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "labels" = {
        "app.kubernetes.io/instance"   = "humiocluster"
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "humio"
        "humio.com/node-pool"          = "${var.logscale_cluster_name}-ingest-only"
      }
      "name"      = "${var.logscale_cluster_name}-advanced"
      "namespace" = var.logscale_cluster_k8s_namespace_name
    }
    "spec" = {
      "dnsNames" = [
        "${var.logscale_cluster_name}-advanced.${var.logscale_cluster_k8s_namespace_name}",
        "${var.logscale_cluster_name}-advanced-headless.${var.logscale_cluster_k8s_namespace_name}",
      ]
      "issuerRef" = {
        "name" = "humiocluster"
      }
      "secretName" = "${var.logscale_cluster_name}-advanced"
    }
  }

  depends_on = [kubernetes_namespace.logscale]
}

# Create a secret for the Humio license
resource "kubernetes_secret" "humiocluster_license" {
  metadata {
    name      = "${var.logscale_cluster_name}-license"
    namespace = var.logscale_cluster_k8s_namespace_name
  }
  data = {
    humio-license-key = var.humiocluster_license
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
resource "random_password" "static_admin_password" {
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
}
