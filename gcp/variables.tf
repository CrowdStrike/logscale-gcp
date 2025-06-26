# Variable definitions
# These varriables can be overriden with the _override.tf file or by specifying then on the command line
# using -var
# Many of these varibales are undefined and interpolated in the Terraform files

# this varibale is used to prefix all resources created
variable "infrastructure_prefix" {
  default = "logscale"
}

# Bastion host enabled
variable "bastion_host_enabled" {
    type = bool
    default = true
}

# Random string used for cluster prefixes
resource "random_string" "env_identifier_rand" {
  length  = 4
  special = false
  lower   = true
  upper   = false
}


# GCP Region
variable "region" {
  default = "us-central1"
}

# GCP Zone
variable "zone" {
  default = "us-central1-a"
}

# Project ID is unset and must be supplied using -var project_id= or using the _ovverride.tf file
variable "project_id" {
  type = string
}

# GKE minimum master version
variable "min_master_version" {
  default = "1.31.8-gke.1045000"
}


# Nodepool GKE version
variable "node_pool_version" {
  default = "1.31.7-gke.1265000"
}

# Max pods per mode
variable "max_pods_per_node" {
  default = "20"
}

# GKE is a private cluster by default
variable "private_cluster" {
  default = "true"
}

# GKE private nodes
variable "private_nodes" {
  default = "true"
}

# Remove the default node pool
variable "remove_default_node_pool" {
  default = "true"
}

# Node pool auth scopes
variable "node_pool_auth_scopes" {
  type = list(string)

  default = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
  ]
}

# GCP logging service
variable "logging_service" {
  default = "logging.googleapis.com/kubernetes"
}

# GCP Monitoring service
variable "monitoring_service" {
  default = "monitoring.googleapis.com/kubernetes"
}

# Maintenance policy for when auto-update is enabled
variable "maintenance_policy_start_time" {
  default = "05:00"
}

# Enable network policies
variable "network_policy" {
  default = true
}

# Disable VPA
variable "vpa_enabled" {
  default = false
}

# Disable Cloudrun
variable "cloudrun_disabled" {
  default = true
}

# DNS Cache config disabled
variable "dns_cache_config_enabled" {
  default = false
}

# DOn't issue client certificate
variable "issue_client_certificate" {
  default = false
}

# Logscale Cluster Name
variable "name" {
  type    = string
  default = "logscale"
}

# Image node pools will use
variable "image_type" {
  type    = string
  default = "COS_CONTAINERD"
}

# Enable shielded nodes
variable "enable_shielded_nodes" {
  type    = bool
  default = true
}

# VPC CIDR
variable "cluster_ipv4_cidr_block" {
  type    = string
  default = "10.0.0.0/14"
}

# GKE Services CIDR
variable "services_ipv4_cidr_block" {
  type    = string
  default = "172.16.1.0/24"
}

# GKE Control plane CIDR 
variable "master_ipv4_cidr_block" {
  type    = string
  default = "172.16.0.0/28"
}

# GCP CIDR range
variable "gcp_cidr_range" {
  type    = string
  default = "10.128.0.0/20"
}

# GCP Subnetwork Proxy Name
variable "gcp_subnetwork_proxy_name" {
  type    = string
  default = ""
}

# GCP Network Router Name
variable "gcp_network_router_name" {
  type    = string
  default = ""
}

# GCP Subnetwork Proxy CIDR Range
variable "gcp_subnetwork_proxy_cidr_range" {
  type    = string
  default = "10.129.0.0/20"
}



# LogScale bucket storage bucket name
variable "gcs_bucket_name" {
  type    = string
  default = ""
}


# LogScale GCS access logs bucket
variable "logscale_access_logs_bucket" {
  type    = string
  default = ""
}

# GKE Cluster Service Account
variable "logscale_cluster_k8s_service_account_name" {
  type    = string
  default = ""
}

# Basition Service Account Name
variable "logscale_bastion_sa_name" {
  type    = string
  default = ""
}

# VPC Network Name
variable "gcp_network_name" {
  type    = string
  default = ""
}

# VPC Subnetwork Name
variable "gcp_subnetwork_name" {
  type    = string
  default = ""
}

# Bastion Machine Type
variable "bastion_machine_type" {
  type    = string
  default = "e2-standard-2"
}

# Bastion Image Type
variable "bastion_image_type" {
  type    = string
  default = "ubuntu-2004-focal-v20230918"
}

# Bastion Instance Name
variable "bastion_instance_name" {
  type    = string
  default = ""
}

# LogScale Kubernetes Namespace
variable "logscale_cluster_k8s_namespace_name" {
  default = "logging"
  type    = string
}

# Override Terraform Service Account Email
variable "terraform_gcp_sa_email" {
  type    = string
  default = ""
}

# LogScale GKE Cluster Name
variable "logscale_gke_cluster_name" {
  type    = string
  default = ""
}

# Override Terraform Service Account Name
variable "logscale_tf_service_account_name" {
  type    = string
  default = ""
}

# GCE Ingress IP Name
variable "gce_ingress_ip_name" {
  type    = string
  default = ""
}

# VPC NAT IP Name
variable "gcp_network_nat_ip_name" {
  type    = string
  default = ""
}

# VPC Router NAT Name
variable "gcp_network_router_nat_name" {
  type    = string
  default = ""
}

# LogScale Cluster Type
variable "logscale_cluster_type" {
  default = "basic"
  type    = string
  validation {
    condition     = contains(["basic", "ingress", "internal-ingest"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, , or internal-ingest"
  }
}

# LogScale Cluster Size
variable "logscale_cluster_size" {
  default = "xsmall"
  type    = string
  validation {
    condition     = contains(["xsmall", "small", "medium", "large", "xlarge"], var.logscale_cluster_size)
    error_message = "logscale_cluster_size must be one of: xsmall, small, medium, large, or xlarge"
  }
}

# Local Variables
locals {
  # Render a template of available cluster sizes
  cluster_size_template = jsondecode(templatefile("${path.module}/cluster_size.tpl", {}))
  cluster_size_rendered = {
    for key in keys(local.cluster_size_template) :
    key => local.cluster_size_template[key] #[var.environment] # optional - values per environment
  }
}

# Output variables used by LogScale GCP Components
output "logscale_cluster_name" {
  value = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}")
}

output "logscale_cluster_identifier" {
  value = random_string.env_identifier_rand.result
}

output "logscale_cluster_size" {
  value = var.logscale_cluster_size
}

output "logscale_cluster_type" {
  value = var.logscale_cluster_type
}

output "logscale_cluster_definitions" {
  value = local.cluster_size_rendered
}

output "logscale_bucket_storage" {
  value = google_storage_bucket.logscale_bucket_storage.name
}

output "logscale_gce_ingress_ip" {
  value = google_compute_global_address.gce_ingress_ip.name
}

output "logscale_cluster_region" {
  value = var.region
}

output "logscale_cluster_zone" {
  value = var.zone
}

output "logscale_cluster_project_id" {
  value = var.project_id
}

