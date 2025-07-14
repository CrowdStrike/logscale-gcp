# Certificate for external GCE ingress
resource "kubernetes_manifest" "google_managed_certificate" {
  manifest = {
    "apiVersion" = "networking.gke.io/v1"
    "kind"       = "ManagedCertificate"
    "metadata" = {
      "name"      = "${local.logscale_cluster_name}-google-managed-certificate"
      "namespace" = "logging"
    }
    "spec" = {
      "domains" = ["${var.public_url}"]
    }
  }
}

# Basic cluster type nodeport
resource "kubernetes_service" "logscale_basic_nodeport" {
  count = contains(["basic"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-nodeport"
    namespace = kubernetes_namespace.logscale.id
    annotations = {
      "cloud.google.com/backend-config" = "{\"default\": \"${local.logscale_cluster_name}-healthcheck-config\"}"
      "cloud.google.com/app-protocols"  = "{\"logscale-port\":\"HTTPS\"}"
    }
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "humio"
    }
    port {
      port        = 8080
      target_port = 8080
      name        = "logscale-port"
    }
    type = "NodePort"
  }

  depends_on = [
    helm_release.cert-manager,
    kubernetes_manifest.humio_cluster_type_basic[0]
  ]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"]
    ]
  }

}

# Basic type cluster ingress backend
resource "kubernetes_manifest" "logscale_basic_ingress_backend" {
  count = contains(["basic"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind"       = "BackendConfig"
    "metadata" = {
      "labels" = {
        "app.kubernetes.io/name" = "humio"
      }
      "name"      = "${local.logscale_cluster_name}-healthcheck-config"
      "namespace" = "${kubernetes_namespace.logscale.id}"
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec"   = 15
        "timeoutSec"         = 10
        "healthyThreshold"   = 1
        "requestPath"        = "/"
        "type"               = "HTTPS"
        "unhealthyThreshold" = 3
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_basic[0]
  ]

}

# Basic type cluster ingress resource
resource "kubernetes_ingress_v1" "logscale_basic_ingress" {
  count = contains(["basic"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-basic-ingress"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = "${local.logscale_gce_ingress_ip}"
      "kubernetes.io/ingress.allow-http"            = "false"
      "networking.gke.io/managed-certificates" : "${local.logscale_cluster_name}-google-managed-certificate"
    }
  }
  spec {
    default_backend {
      service {
        name = "${local.logscale_cluster_name}-nodeport"
        port {
          number = 8080
        }
      }
    }

    rule {
      http {
        path {
          backend {
            service {
              name = "${local.logscale_cluster_name}-nodeport"
              port {
                number = 8080
              }
            }
          }

          path = "/"
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_basic[0]
  ]
}

# Ingress cluster type nodeport
resource "kubernetes_service" "logscale_nodeport_ingress" {
  count = contains(["ingress"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-nodeport-ingress"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "cloud.google.com/backend-config" = "{\"default\": \"${local.logscale_cluster_name}-ingress-healthcheck-config\"}"
      "cloud.google.com/app-protocols"  = "{\"logscale-port\":\"HTTPS\"}"
    }
  }
  spec {
    selector = {
      "humio.com/node-pool" = "${local.logscale_cluster_name}-ingress-only"
    }
    port {
      port        = 8080
      target_port = 8080
      name        = "logscale-port"
    }
    type = "NodePort"
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_ingress[0]
  ]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"]
    ]
  }
}

# Ingress cluster type ingress backend
resource "kubernetes_manifest" "logscale_ingress_ingress_backend" {
  count = contains(["ingress"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind"       = "BackendConfig"
    "metadata" = {
      "labels" = {
        "app.kubernetes.io/name" = "humio"
      }
      "name"      = "${local.logscale_cluster_name}-ingress-healthcheck-config"
      "namespace" = "${kubernetes_namespace.logscale.id}"
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec"   = 15
        "timeoutSec"         = 10
        "healthyThreshold"   = 1
        "requestPath"        = "/"
        "type"               = "HTTPS"
        "unhealthyThreshold" = 3
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_ingress[0]
  ]
}

# Ingress cluster type ingress resource
resource "kubernetes_ingress_v1" "logscale_ingress_ingress" {
  count = contains(["ingress"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "logscale-ingress"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = "${local.logscale_gce_ingress_ip}"
      "kubernetes.io/ingress.allow-http"            = "false"
      "networking.gke.io/managed-certificates" : "${local.logscale_cluster_name}-google-managed-certificate"
    }
  }
  spec {
    default_backend {
      service {
        name = "${local.logscale_cluster_name}-nodeport-ingress"
        port {
          number = 8080
        }
      }
    }

    rule {
      http {
        path {
          backend {
            service {
              name = "${local.logscale_cluster_name}-nodeport-ingress"
              port {
                number = 8080
              }
            }
          }

          path = "/"
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_ingress[0]
  ]
}

# Internal-ingress cluster type nodeport for UI
resource "kubernetes_service" "logscale_nodeport_ui" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-nodeport-ui"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "cloud.google.com/backend-config" = "{\"default\": \"${local.logscale_cluster_name}-ui-healthcheck-config\"}"
      "cloud.google.com/app-protocols"  = "{\"logscale-port\":\"HTTPS\"}"
    }
  }
  spec {
    selector = {
      "humio.com/node-pool" = "${local.logscale_cluster_name}-ui-only"
    }
    port {
      port        = 8080
      target_port = 8080
      name        = "logscale-port"
    }
    type = "NodePort"
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"]
    ]
  }
}

# Internal-ingress cluster type backend for UI
resource "kubernetes_manifest" "logscale_ingress_ui_backend" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind"       = "BackendConfig"
    "metadata" = {
      "labels" = {
        "app.kubernetes.io/name" = "humio"
      }
      "name"      = "${local.logscale_cluster_name}-ui-healthcheck-config"
      "namespace" = "${kubernetes_namespace.logscale.id}"
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec"   = 15
        "timeoutSec"         = 10
        "healthyThreshold"   = 1
        "requestPath"        = "/"
        "type"               = "HTTPS"
        "unhealthyThreshold" = 3
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]
}

# Internal-ingress cluster type ingress resource for UI
resource "kubernetes_ingress_v1" "logscale_ingress_ui" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-ui-ingress"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = "${local.logscale_gce_ingress_ip}"
      "kubernetes.io/ingress.allow-http"            = "false"
      "networking.gke.io/managed-certificates" : "${local.logscale_cluster_name}-google-managed-certificate"
    }
  }
  spec {
    default_backend {
      service {
        name = "${local.logscale_cluster_name}-nodeport-ui"
        port {
          number = 8080
        }
      }
    }

    rule {
      http {
        path {
          backend {
            service {
              name = "${local.logscale_cluster_name}-nodeport-ui"
              port {
                number = 8080
              }
            }
          }

          path = "/"
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]
}

# Internal-ingress cluster type nodeport for internal ingest
resource "kubernetes_service" "logscale_nodeport_ingest" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-nodeport-ingest"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "cloud.google.com/backend-config" = "{\"default\": \"${local.logscale_cluster_name}-ingest-healthcheck-config\"}"
      "cloud.google.com/app-protocols"  = "{\"logscale-port\":\"HTTPS\"}"
      "cloud.google.com/neg"            = "{\"ingress\": true}"
    }
  }
  spec {
    selector = {
      "humio.com/node-pool" = "${local.logscale_cluster_name}-ingest-only"
    }
    port {
      port        = 8080
      target_port = 8080
      name        = "logscale-port"
    }
    type = "NodePort"
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"],
      metadata[0].annotations["cloud.google.com/neg-status"]
    ]
  }

}

# Internal-ingress cluster type backend for internal ingest
resource "kubernetes_manifest" "logscale_ingress_ingest_backend" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind"       = "BackendConfig"
    "metadata" = {
      "labels" = {
        "app.kubernetes.io/name" = "humio"
      }
      "name"      = "${local.logscale_cluster_name}-ingest-healthcheck-config"
      "namespace" = "logging"
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec"   = 15
        "timeoutSec"         = 10
        "healthyThreshold"   = 1
        "requestPath"        = "/"
        "type"               = "HTTPS"
        "unhealthyThreshold" = 3
      }
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]
}

# Internal-ingress cluster type ingress resource for internal ingest
resource "kubernetes_ingress_v1" "logscale_ingress_ingest" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  metadata {
    name      = "${local.logscale_cluster_name}-ingest-ingress"
    namespace = var.logscale_cluster_k8s_namespace_name
    annotations = {
      "kubernetes.io/ingress.class"      = "gce"
      "kubernetes.io/ingress.allow-http" = "false"
      "kubernetes.io/ingress.class"      = "gce-internal"
    }
  }
  spec {
    default_backend {
      service {
        name = "${local.logscale_cluster_name}-nodeport-ingest"
        port {
          number = 8080
        }
      }
    }

    rule {
      http {
        path {
          backend {
            service {
              name = "${local.logscale_cluster_name}-nodeport-ingest"
              port {
                number = 8080
              }
            }
          }

          path = "/"
        }
      }
    }
    tls {
      secret_name = "${local.logscale_cluster_name}-internal-ingest"
    }
  }

  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]
}

# Certificate used for internal load balancer
resource "kubernetes_manifest" "logscale_internal_ingest_cert" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "labels" = {
        "app.kubernetes.io/instance"   = "humiocluster"
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/name"       = "humio"
        "humio.com/node-pool"          = "${local.logscale_cluster_name}-ingest-only"
      }
      "name"      = "${local.logscale_cluster_name}-internal-ingest"
      "namespace" = "logging"
    }
    "spec" = {
      "dnsNames" = [
        "${local.logscale_cluster_name}-internal-ingest.logging",
        "${local.logscale_cluster_name}-internal-ingest-headless.logging",
      ]
      "issuerRef" = {
        "name" = "humiocluster"
      }
      "secretName" = "${local.logscale_cluster_name}-internal-ingest"
    }
  }
  depends_on = [
    kubernetes_manifest.humio_cluster_type_internal_ingest[0]
  ]
}