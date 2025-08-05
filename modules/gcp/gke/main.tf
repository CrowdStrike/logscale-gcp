# GKE Cluster
resource "google_container_cluster" "logscale" {
  name     = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}-${var.env_identifier_rand}-gke")
  location = var.region
  provider = google-beta

  min_master_version    = var.min_master_version
  enable_shielded_nodes = var.enable_shielded_nodes
  logging_service       = var.logging_service
  monitoring_service    = var.monitoring_service

  network    = var.network_name
  subnetwork = var.subnetwork_name

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = var.remove_default_node_pool
  initial_node_count       = 1
  master_authorized_networks_config {
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.cluster_ipv4_cidr_block  # Custom CIDR block for the cluster
    services_ipv4_cidr_block = var.services_ipv4_cidr_block # Custom CIDR block for services
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  private_cluster_config {
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    enable_private_nodes    = var.private_nodes
    enable_private_endpoint = true
  }
  # The absence of a user and pwd here disables basic auth
  master_auth {
    #  username = ""
    #  password = ""
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_policy_start_time
    }
  }

  release_channel {
    channel = "UNSPECIFIED"
  }

  resource_labels = {
    kubernetescluster = var.name
  }

  vertical_pod_autoscaling {
    enabled = var.vpa_enabled
  }

  lifecycle {
    # ignore changes to nodepool so it doesn't recreate default node pool with every changes
    # ignore changes to network and subnetwork so it doesn't fill up diff with simple changes
    ignore_changes = [
      node_pool,
      network,
      subnetwork,
      remove_default_node_pool,
    ]
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "random_string" "node_pool_suffix" {
  length  = 4
  special = false
  upper   = false
  lower   = true
  numeric = false
}

locals {
  cluster_size_rendered = var.cluster_size_definitions
}
