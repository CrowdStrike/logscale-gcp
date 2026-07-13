# GCP Post-Install Module
#
# Creates GCP-specific Kubernetes resources (services, ingresses, backend
# configs, encryption secrets) that supplement the shared logscale-kubernetes
# deployment. All resources require the LogScale namespace to exist.
#
# The namespace is created by modules/kubernetes/pre-install which runs
# before this module in the workflow DAG.

# Google Managed Certificate for external GCE ingress
resource "kubernetes_manifest" "google_managed_certificate" {
  count = var.enable_gke_ingress ? 1 : 0
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
    "spec" = merge(
      {
        "healthCheck" = {
          "checkIntervalSec"   = 15
          "timeoutSec"         = 10
          "healthyThreshold"   = 1
          "requestPath"        = "/api/v1/status"
          "type"               = "HTTPS"
          "unhealthyThreshold" = 3
        }
      },
      var.cloud_armor_policy_name != "" ? {
        "securityPolicy" = {
          "name" = var.cloud_armor_policy_name
        }
      } : {}
    )
  }

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

}

# Certificate for internal load balancer (advanced type only)
# REMOVED: kubernetes_manifest for Certificate resource
# Reason: cert-manager auto-creates the Certificate via the ingress annotation
# "cert-manager.io/issuer" on the internal ingress (logscale_gcp_internal_ingress).
# This avoids the CRD plan-time validation issue where kubernetes_manifest
# requires CRDs to exist before terraform plan can succeed.

# Resolve the encryption key for DR standby: prefer explicit override, then remote state
locals {
  dr_resolved_encryption_key = var.existing_gcs_encryption_key != "" ? var.existing_gcs_encryption_key : (
    var.primary_remote_state != null ? try(var.primary_remote_state.outputs.gcs_storage_encryption_key, "") : ""
  )
}

# Create a random key for encrypting data in bucket storage
resource "random_password" "gcp_storage_encryption_password" {
  count   = var.dr != "standby" ? 1 : 0 # Only create if not standby (primary/active creates key)
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
    gcp-storage-encryption-key = var.dr == "standby" ? local.dr_resolved_encryption_key : (
      length(random_password.gcp_storage_encryption_password) > 0 ? random_password.gcp_storage_encryption_password[0].result : ""
    )
  }

  lifecycle {
    precondition {
      condition     = var.dr != "standby" || local.dr_resolved_encryption_key != ""
      error_message = "DR standby requires a non-empty encryption key from primary. Check that primary_remote_state is configured and the primary cluster has completed deployment (gcs_storage_encryption_key output must exist)."
    }
  }

}

# Create DR recovery encryption key secret
# Exists whenever a resolved encryption key is available (standby AND promoted active).
# Must NOT be gated on dr=="standby" because promotion (standby→active) still needs
# this secret for LogScale's GCP_RECOVER_FROM_ENCRYPTION_KEY secretKeyRef.
resource "kubernetes_secret" "gcp_dr_storage_encryption_key" {
  count = local.dr_resolved_encryption_key != "" ? 1 : 0

  metadata {
    name      = var.gcp_recover_from_encryption_key_secret_name != "" ? var.gcp_recover_from_encryption_key_secret_name : "dr-secondary-gcs-storage-encryption"
    namespace = var.logscale_cluster_k8s_namespace_name
  }
  data = {
    (var.gcp_recover_from_encryption_key_secret_key != "" ? var.gcp_recover_from_encryption_key_secret_key : "gcp-storage-encryption-key") = local.dr_resolved_encryption_key
  }

  lifecycle {
    precondition {
      condition     = local.dr_resolved_encryption_key != ""
      error_message = "DR recovery encryption key secret would be created empty. The primary cluster's encryption key could not be read from remote state. Verify remote state connectivity and that the primary cluster has completed deployment."
    }
  }

}

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
    "cert-manager.io/issuer"           = var.resource_name_prefix
  }

  # Use humio_cluster_name_prefix (full prefix with random modifier) when available,
  # otherwise fall back to resource_name_prefix for backwards compatibility
  selector_name_prefix = coalesce(var.humio_cluster_name_prefix, var.resource_name_prefix)
}

# NodePort service for GCP external ingress
resource "kubernetes_service" "logscale_nodeport" {
  metadata {
    name      = "${var.logscale_cluster_name}-nodeport"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = merge(
      local.gcp_service_annotations,
      {
        # Enable NEGs so external load balancers (GLB) can target per-zone endpoints
        "cloud.google.com/neg" = "{\"ingress\": true}"
      }
    )
  }

  spec {
    type = "NodePort"
    # Simple selector matching all humio pods
    # Note: For DR standby and advanced/dedicated-ui types, the root module main.tf
    # overrides this service with node-pool specific selectors AFTER module.logscale runs.
    selector = {
      "app.kubernetes.io/name" = "humio"
    }
    port {
      port        = 8080
      target_port = 8080
      node_port   = var.logscale_ui_nodeport
      name        = "logscale-port"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"],
      # Selector is managed by root main.tf for DR standby and advanced types
      spec[0].selector
    ]
  }

}

locals {
  instance_group_url  = var.enable_glb_named_port && length(var.instance_group_urls) > 0 ? var.instance_group_urls[0] : ""
  instance_group_zone = local.instance_group_url != "" ? element(split("/", local.instance_group_url), index(split("/", local.instance_group_url), "zones") + 1) : ""
  instance_group_name = local.instance_group_url != "" ? element(split("/", replace(local.instance_group_url, "instanceGroupManagers", "instanceGroups")), length(split("/", local.instance_group_url)) - 1) : ""
}

resource "google_compute_instance_group_named_port" "glb_named_port" {
  count = var.enable_glb_named_port && local.instance_group_url != "" ? 1 : 0

  project = var.project_id
  zone    = local.instance_group_zone
  group   = local.instance_group_name
  name    = "https"
  port    = var.logscale_ui_nodeport

  depends_on = [kubernetes_service.logscale_nodeport]
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
    type = "NodePort"
    selector = {
      "humio.com/node-pool" = "${local.selector_name_prefix}-ingest-only"
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


}

# GKE EXTERNAL INGRESS (Service-based routing)
resource "kubernetes_ingress_v1" "logscale_gke_ingress" {
  count = var.enable_gke_ingress ? 1 : 0
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

  depends_on = [kubernetes_service.logscale_nodeport]
}

# GCP INTERNAL UI INGRESS (ingress_mode=internal, VPC-only access)
resource "kubernetes_ingress_v1" "logscale_internal_ui_ingress" {
  count = var.enable_internal_ingress ? 1 : 0

  metadata {
    name      = "${var.logscale_cluster_name}-internal-ui"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "kubernetes.io/ingress.class"      = "gce-internal"
      "kubernetes.io/ingress.allow-http" = "false"
    }
  }

  spec {
    default_backend {
      service {
        name = kubernetes_service.logscale_nodeport.metadata[0].name
        port {
          number = 8080
        }
      }
    }

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

  depends_on = [kubernetes_service.logscale_nodeport]
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

  depends_on = [kubernetes_service.logscale_gcp_internal_ingest_nodeport]
}
