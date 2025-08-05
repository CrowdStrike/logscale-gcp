# This nodepol is created when the ingress logscale_cluster_type is defined
resource "google_container_node_pool" "logscale_ingress_node_pool" {
  count      = contains(["ingress"], var.logscale_cluster_type) ? 1 : 0
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-ingress-${var.env_identifier_rand}" : "${var.infrastructure_prefix}-${var.env_identifier_rand}-np-ingress-${var.env_identifier_rand}")
  location   = var.region
  cluster    = google_container_cluster.logscale.name
  node_count = ceil(local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingress_node_count"] / 3)
  version    = var.node_pool_version

  autoscaling {
    min_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingress_min_node_count"]
    max_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingress_max_node_count"]
  }

  node_config {
    preemptible  = false
    image_type   = var.image_type
    machine_type = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingress_machine_type"]

    disk_size_gb = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingress_root_disk_size"]
    disk_type    = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingress_root_disk_type"]
    oauth_scopes = var.node_pool_auth_scopes

    labels = {
      managed_by = "terraform"
      k8s-app    = "logscale-ingress-${var.env_identifier_rand}"
    }

    metadata = {
      block-project-ssh-keys = true
    }

  }

  management {
    auto_repair  = "true"
    auto_upgrade = "false"
  }

  # This would ensure that node pool which you want to replace stays up until the replacement pool has been created.
  lifecycle {
    create_before_destroy = true
    # ignore changes to metadata as it's causing force replacement of nodepool
    ignore_changes = [
      node_config[0].metadata,
    ]
  }

  timeouts {
    delete = "1h"
  }

  depends_on = [
    google_container_cluster.logscale,
  ]
}