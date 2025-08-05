# Random string used for cluster prefixes
resource "random_string" "env_identifier_rand" {
  length  = 4
  special = false
  lower   = true
  upper   = false
}

# Creates a basion host, this can be disabled by setting var.bastion_host_enabled = false when applying or by
# using the override file

resource "google_compute_instance" "bastion" {
  count = var.bastion_host_enabled ? 1 : 0 
  name         = (var.bastion_instance_name != "" ? var.bastion_instance_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bastion")
  machine_type = var.bastion_machine_type
  zone         = var.zone
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = var.bastion_image_type
    }
  }

  network_interface {
    network    = module.vpc.network_name
    subnetwork = module.vpc.subnetwork_name
  }

  shielded_instance_config {
    enable_vtpm = true
  }

  metadata = {
    block-project-ssh-keys = true
  }

  metadata_startup_script = <<-EOF
  #!/bin/bash
  sudo apt-get update
  # Install kubectl
  sudo apt-get install -y apt-transport-https ca-certificates curl
  sudo mkdir -p /etc/apt/keyrings/
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  # Install gcloud-sdk
  sudo snap remove google-cloud-cli
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
  sudo apt-get update && sudo apt-get install -y google-cloud-cli kubectl google-cloud-cli-gke-gcloud-auth-plugin gnupg software-properties-common
  # Install terraform
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt-get install -y terraform tinyproxy
  sudo sed -i "225i Allow localhost" /etc/tinyproxy/tinyproxy.conf
  sudo systemctl restart tinyproxy.service
  EOF

  lifecycle {
    ignore_changes = [
      metadata.ssh_keys
    ]
  }

  service_account {
    email  = google_service_account.bastion_service_account[0].email
    scopes = ["cloud-platform"]
  }

  depends_on = [
    module.vpc,
    google_service_account.bastion_service_account,
  ]
}

# GCS Buckets


#Bucket used for logging
resource "google_storage_bucket" "log_bucket" {
  name = (var.logscale_access_logs_bucket != "" ? var.logscale_access_logs_bucket : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-logs")

  # should this move to region?
  location = "US"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

# Local variables for cluster size
locals {
  cluster_size_template = jsondecode(templatefile("${path.module}/cluster_size.tpl", {}))
  cluster_size_rendered = {
    for key in keys(local.cluster_size_template) :
    key => local.cluster_size_template[key]
  }
  logscale_cluster_name = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}")
}

# VPC Module
module "vpc" {
  source = "./modules/gcp/vpc"
  
  # Basic configuration
  project_id            = var.project_id
  region                = var.region
  infrastructure_prefix = var.infrastructure_prefix
  
  # Network configuration
  gcp_network_name                    = var.gcp_network_name
  gcp_subnetwork_name                 = var.gcp_subnetwork_name
  gcp_cidr_range                      = var.gcp_cidr_range
  gcp_subnetwork_proxy_name           = var.gcp_subnetwork_proxy_name
  gcp_subnetwork_proxy_cidr_range     = var.gcp_subnetwork_proxy_cidr_range
  
  # LogScale configuration
  logscale_cluster_type = var.logscale_cluster_type
  
  # Static IP names
  gce_ingress_ip_name           = var.gce_ingress_ip_name
  gcp_network_nat_ip_name       = var.gcp_network_nat_ip_name
  gcp_network_router_name       = var.gcp_network_router_name
  gcp_network_router_nat_name   = var.gcp_network_router_nat_name
  
  # Random identifier
  env_identifier_rand = random_string.env_identifier_rand.result
}

# GKE Module
module "gke" {
  source = "./modules/gcp/gke"
  
  # Basic configuration
  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  infrastructure_prefix = var.infrastructure_prefix
  name                  = var.name
  
  # Cluster versioning
  min_master_version    = var.min_master_version
  node_pool_version     = var.node_pool_version
  
  # Cluster configuration
  enable_shielded_nodes     = var.enable_shielded_nodes
  logging_service           = var.logging_service
  monitoring_service        = var.monitoring_service
  remove_default_node_pool  = var.remove_default_node_pool
  private_nodes             = var.private_nodes
  vpa_enabled               = var.vpa_enabled
  
  # Network configuration (from VPC module)
  network_name              = module.vpc.network_name
  subnetwork_name           = module.vpc.subnetwork_name
  cluster_ipv4_cidr_block   = var.cluster_ipv4_cidr_block
  services_ipv4_cidr_block  = var.services_ipv4_cidr_block
  master_ipv4_cidr_block    = var.master_ipv4_cidr_block
  
  # Maintenance configuration
  maintenance_policy_start_time = var.maintenance_policy_start_time
  
  # Node pool configuration
  image_type                = var.image_type
  node_pool_auth_scopes     = var.node_pool_auth_scopes
  
  # LogScale specific configuration
  logscale_gke_cluster_name = var.logscale_gke_cluster_name
  logscale_cluster_size     = var.logscale_cluster_size
  logscale_cluster_type     = var.logscale_cluster_type
  cluster_size_definitions  = local.cluster_size_rendered
  
  # Random identifier
  env_identifier_rand = random_string.env_identifier_rand.result
  
  depends_on = [module.vpc]
}

# Kubernetes pre-install module
/*module "kubernetes_pre_install" {
  source = "./modules/kubernetes/pre-install"
  
  # Cluster connection info
  cluster_endpoint       = module.gke.cluster_endpoint
  cluster_ca_certificate = module.gke.cluster_ca_certificate
  cluster_name           = module.gke.cluster_name
  
  # Project and region
  project_id = var.project_id
  region     = var.region
  
  # LogScale configuration
  logscale_cluster_type               = var.logscale_cluster_type
  logscale_cluster_k8s_namespace_name = var.logscale_cluster_k8s_namespace_name
  public_url                          = var.public_url
  
  # Pass computed values
  logscale_cluster_name     = local.logscale_cluster_name
  logscale_gce_ingress_ip   = module.vpc.gce-ingress-external-static-ip
  
  depends_on = [module.gke, module.vpc]
}*/


resource "google_storage_bucket" "logscale_bucket_storage" {
  name     = (var.gcs_bucket_name != "" ? var.gcs_bucket_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bucket-storage")
  location = var.region

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 1
    }
    action {
      type = "Delete"
    }
  }

  logging {
    log_bucket        = google_storage_bucket.log_bucket.name
    log_object_prefix = "access-logs/"
  }
}

# Workload identity for LogScale bucket storage access
module "gcs_workload_identity" {
  source       = "git::https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git//modules/workload-identity?ref=165a4ae3d5a8d8235b30fac8edd09fe7030d2046"
  name         = (var.logscale_cluster_k8s_service_account_name != "" ? var.logscale_cluster_k8s_service_account_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-wl-identity")
  namespace    = var.logscale_cluster_k8s_namespace_name
  project_id   = var.project_id
  cluster_name = module.gke.cluster_name

  automount_service_account_token = true
  annotate_k8s_sa                 = false
  use_existing_k8s_sa             = true
}

# Role for workload identity
resource "google_storage_bucket_iam_member" "members" {
  bucket = google_storage_bucket.logscale_bucket_storage.name
  role   = "roles/storage.objectUser"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}

# Binding for service accounts
resource "google_service_account_iam_binding" "gcs_wl_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gcs_workload_identity.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${local.logscale_cluster_name}-humio]",
    "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${local.logscale_cluster_name}-wl-identity]",
  ]
}

data "google_project" "project" {}

# Terraform Service Account
resource "google_service_account" "tf_service_account" {
  account_id   = (var.logscale_tf_service_account_name != "" ? var.logscale_tf_service_account_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-tf-sa")
  display_name = "Terraform GCP Service Account"
}

# Bastion Service Account
resource "google_service_account" "bastion_service_account" {
  count = var.bastion_host_enabled ? 1 : 0 
  account_id   = (var.logscale_bastion_sa_name != "" ? var.logscale_bastion_sa_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bastion-sa")
  display_name = "SA for Bastion VM Instance"
}


# Terraform service account roles
resource "google_project_iam_binding" "terraform_gcp_sa_roles" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

# Cloudservices and Terraform service account binding
resource "google_project_iam_binding" "terraform_gcp_sa_editor" {
  project = var.project_id
  role    = "roles/editor"
  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}",
    "serviceAccount:${data.google_project.project.number}@cloudservices.gserviceaccount.com"
  ]

  depends_on = [
    google_service_account.tf_service_account,
  ]
}
