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
  default = "1.32.4-gke.1767000"
}


# Nodepool GKE version
variable "node_pool_version" {
  default = "1.32.4-gke.1767000"
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
    condition     = contains(["basic", "ingress", "advanced"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, ingress , or advanced"
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

# Output variables used by LogScale GCP Components

output "logscale_bucket_storage" {
  value = google_storage_bucket.logscale_bucket_storage.name
}

output "logscale_gce_ingress_ip" {
  value = module.vpc.gce_ingress_ip_name
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

# Variable definitions
# These varriables can be overriden with the _override.tf file or by specifying then on the command line
# using -var
# Many of these varibales are undefined and interpolated in the Terraform files


# Public URL of the cluster
variable "public_url" {
  type    = string
  default = "gcpwccq.humio.net"
}

# Remote state where the LogScale GCP Terraform state is stored
variable "logscale_gcp_tf_state_bucket" {
  type    = string
  default = "xxxxx-logscale-terraform-state-v1"
}

variable "humiocluster_license" {
  description = "LogScale license key"
  type        = string
  sensitive   = true
}

variable "humio_operator_version" {
  description = "Humio operator version"
  type        = string
  default     = "0.21.0"
}

variable "humio_operator_extra_values" {
  description = "Extra values for Humio operator"
  type        = map(string)
  default     = {}
}

variable "cm_version" {
  description = "Cert-manager version"
  type        = string
  default     = "v1.13.0"
}

variable "cm_repo" {
  description = "Cert-manager repository"
  type        = string
  default     = "https://charts.jetstack.io"
}

variable "cm_namespace" {
  description = "Cert-manager namespace"
  type        = string
  default     = "cert-manager"
}

variable "ca_server" {
  description = "Certificate authority server"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "issuer_name" {
  description = "Certificate issuer name"
  type        = string
  default     = "letsencrypt-prod"
}

variable "issuer_email" {
  description = "Certificate issuer email"
  type        = string
}

variable "issuer_kind" {
  description = "Certificate issuer kind"
  type        = string
  default     = "ClusterIssuer"
}

variable "issuer_private_key" {
  description = "Certificate issuer private key"
  type        = string
  default     = "letsencrypt-prod"
}

variable "humio_operator_chart_version" {
  description = "Humio operator chart version"
  type        = string
  default     = "0.21.0"
}

variable "logscale_image_version" {
  description = "LogScale image version"
  type        = string
  default     = "1.131.1"
}

variable "kubeconfig_filepath" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}














