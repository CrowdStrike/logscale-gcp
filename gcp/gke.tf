# GKE Cluster
resource "google_container_cluster" "logscale" {
  name     = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-gke")
  location = var.region
  provider = google-beta

  min_master_version    = var.min_master_version
  enable_shielded_nodes = var.enable_shielded_nodes
  logging_service       = var.logging_service
  monitoring_service    = var.monitoring_service

  network    = google_compute_network.network.name
  subnetwork = google_compute_subnetwork.subnetwork.name

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

# Every logscale_cluster_type will have this nodepool defined, depending on 
# on the type this node pool may or may not be used by the ingress backend 
resource "google_container_node_pool" "logscale_node_pool" {
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-logscale-${random_string.node_pool_suffix.result}" : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-np-logscale-${random_string.node_pool_suffix.result}")
  location   = var.region
  cluster    = google_container_cluster.logscale.name
  node_count = ceil(local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_node_count"] / 3)
  version    = var.node_pool_version

  autoscaling {
    min_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_min_node_count"]
    max_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_max_node_count"]
  }

  node_config {
    preemptible  = false
    image_type   = var.image_type
    machine_type = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_machine_type"]

    disk_size_gb = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_root_disk_size"]
    disk_type    = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_root_disk_type"]
    oauth_scopes = var.node_pool_auth_scopes

    local_nvme_ssd_block_config {
      local_ssd_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_digest_local_ssd_count"]
    }

    labels = {
      managed_by   = "terraform"
      k8s-app      = "logscale-${random_string.env_identifier_rand.result}"
      storageclass = "nvme"
    }

    metadata = {
      block-project-ssh-keys = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
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
    google_project_iam_binding.terraform_gcp_sa_editor
  ]
}

# Every logscale_cluster_type will have this nodepool defined
resource "google_container_node_pool" "kafka_node_pool" {
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-kafka-${random_string.node_pool_suffix.result}" : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-np-kafka-${random_string.node_pool_suffix.result}")
  location   = var.region
  cluster    = google_container_cluster.logscale.name
  node_count = ceil(local.cluster_size_rendered[var.logscale_cluster_size]["kafka_broker_node_count"] / 3)
  version    = var.node_pool_version

  autoscaling {
    min_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["kafka_broker_min_node_count"]
    max_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["kafka_broker_max_node_count"]
  }

  node_config {
    preemptible  = false
    image_type   = var.image_type
    machine_type = local.cluster_size_rendered[var.logscale_cluster_size]["kafka_broker_machine_type"]

    disk_size_gb = local.cluster_size_rendered[var.logscale_cluster_size]["kafka_broker_root_disk_size"]
    disk_type    = local.cluster_size_rendered[var.logscale_cluster_size]["kafka_broker_root_disk_type"]
    oauth_scopes = var.node_pool_auth_scopes

    labels = {
      managed_by = "terraform"
      k8s-app    = "kafka-${random_string.env_identifier_rand.result}"
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

# Every logscale_cluster_type will have this nodepool defined
resource "google_container_node_pool" "zookeeper_node_pool" {
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-zookeeper-${random_string.node_pool_suffix.result}" : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-np-zookeeper-${random_string.node_pool_suffix.result}")
  location   = var.region
  cluster    = google_container_cluster.logscale.name
  node_count = ceil(local.cluster_size_rendered[var.logscale_cluster_size]["zookeeper_node_count"] / 3)
  version    = var.node_pool_version

  autoscaling {
    min_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["zookeeper_min_node_count"]
    max_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["zookeeper_max_node_count"]
  }

  node_config {
    preemptible  = false
    image_type   = var.image_type
    machine_type = local.cluster_size_rendered[var.logscale_cluster_size]["zookeeper_machine_type"]

    disk_size_gb = local.cluster_size_rendered[var.logscale_cluster_size]["zookeeper_root_disk_size"]
    disk_type    = local.cluster_size_rendered[var.logscale_cluster_size]["zookeeper_root_disk_type"]
    oauth_scopes = var.node_pool_auth_scopes

    labels = {
      managed_by = "terraform"
      k8s-app    = "zookeeper-${random_string.env_identifier_rand.result}"
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

# This nodepol is created when the ingress logscale_cluster_type is defined
resource "google_container_node_pool" "logscale_ingress_node_pool" {
  count      = contains(["ingress"], var.logscale_cluster_type) ? 1 : 0
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-ingress-${random_string.env_identifier_rand.result}" : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-np-ingress-${random_string.env_identifier_rand.result}")
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
      k8s-app    = "logscale-ingress-${random_string.env_identifier_rand.result}"
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


# This nodepol is created when the internal-ingest logscale_cluster_type is defined
resource "google_container_node_pool" "logscale_ingest_node_pool" {
  count      = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-ingest-${random_string.node_pool_suffix.result}" : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-np-ingest-${random_string.node_pool_suffix.result}")
  location   = var.region
  cluster    = google_container_cluster.logscale.name
  node_count = ceil(local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingest_node_count"] / 3)
  version    = var.node_pool_version

  autoscaling {
    min_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingest_min_node_count"]
    max_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingest_max_node_count"]
  }

  node_config {
    preemptible  = false
    image_type   = var.image_type
    machine_type = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingest_machine_type"]

    disk_size_gb = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingest_root_disk_size"]
    disk_type    = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ingest_root_disk_type"]
    oauth_scopes = var.node_pool_auth_scopes

    labels = {
      managed_by = "terraform"
      k8s-app    = "logscale-ingest-${random_string.env_identifier_rand.result}"
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

# This nodepol is created when the internal-ingest logscale_cluster_type is defined
resource "google_container_node_pool" "logscale_ui_node_pool" {
  count      = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  provider   = google-beta
  name       = (var.logscale_gke_cluster_name != "" ? "${var.logscale_gke_cluster_name}-np-ui-${random_string.node_pool_suffix.result}" : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-np-ui-${random_string.node_pool_suffix.result}")
  location   = var.region
  cluster    = google_container_cluster.logscale.name
  node_count = ceil(local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ui_node_count"] / 3)
  version    = var.node_pool_version

  autoscaling {
    min_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ui_min_node_count"]
    max_node_count = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ui_max_node_count"]
  }

  node_config {
    preemptible  = false
    image_type   = var.image_type
    machine_type = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ui_machine_type"]

    disk_size_gb = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ui_root_disk_size"]
    disk_type    = local.cluster_size_rendered[var.logscale_cluster_size]["logscale_ui_root_disk_type"]
    oauth_scopes = var.node_pool_auth_scopes

    labels = {
      managed_by = "terraform"
      k8s-app    = "logscale-ui-${random_string.env_identifier_rand.result}"
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

output "gke_credential_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.logscale.name} --region us-central1 --project ${var.project_id}"
}