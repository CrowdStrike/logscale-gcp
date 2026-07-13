# GCP Pre-Install Module
#
# This module prepares the GKE cluster for LogScale deployment by creating
# the LogScale namespace. This must run before logscale-prereqs which creates
# secrets and certificates in this namespace.
#
# Aligns with the AWS, Azure, and OCI pre-install modules where the namespace
# is guaranteed to exist before any Kubernetes resources are created in it.

resource "kubernetes_namespace_v1" "logscale" {
  metadata {
    name = var.logscale_namespace
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}
