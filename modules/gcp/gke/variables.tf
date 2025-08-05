# Basic cluster configuration
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for the cluster"
  type        = string
}

variable "zone" {
  description = "The GCP zone"
  type        = string
}

variable "infrastructure_prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "logscale"
}

variable "name" {
  description = "Base name for the cluster"
  type        = string
  default     = "logscale"
}

# Cluster versioning
variable "min_master_version" {
  description = "Minimum master version for GKE"
  type        = string
  default     = "1.32.4-gke.1767000"
}

variable "node_pool_version" {
  description = "Node pool GKE version"
  type        = string
  default     = "1.32.4-gke.1767000"
}

# Cluster configuration
variable "enable_shielded_nodes" {
  description = "Enable shielded nodes"
  type        = bool
  default     = true
}

variable "logging_service" {
  description = "GCP logging service"
  type        = string
  default     = "logging.googleapis.com/kubernetes"
}

variable "monitoring_service" {
  description = "GCP monitoring service"
  type        = string
  default     = "monitoring.googleapis.com/kubernetes"
}

variable "remove_default_node_pool" {
  description = "Remove the default node pool"
  type        = bool
  default     = true
}

variable "private_nodes" {
  description = "Enable private nodes"
  type        = bool
  default     = true
}

variable "vpa_enabled" {
  description = "Enable Vertical Pod Autoscaling"
  type        = bool
  default     = false
}

# Network configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnetwork_name" {
  description = "Name of the subnetwork"
  type        = string
}

variable "cluster_ipv4_cidr_block" {
  description = "CIDR block for cluster pods"
  type        = string
  default     = "10.0.0.0/14"
}

variable "services_ipv4_cidr_block" {
  description = "CIDR block for services"
  type        = string
  default     = "172.16.1.0/24"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for master nodes"
  type        = string
  default     = "172.16.0.0/28"
}

# Maintenance configuration
variable "maintenance_policy_start_time" {
  description = "Start time for maintenance window"
  type        = string
  default     = "05:00"
}

# Node pool configuration
variable "image_type" {
  description = "Image type for node pools"
  type        = string
  default     = "COS_CONTAINERD"
}

variable "node_pool_auth_scopes" {
  description = "OAuth scopes for node pools"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
  ]
}

# LogScale specific configuration
variable "logscale_gke_cluster_name" {
  description = "Override name for the GKE cluster"
  type        = string
  default     = ""
}

variable "logscale_cluster_size" {
  description = "Size of the LogScale cluster"
  type        = string
  default     = "xsmall"
  validation {
    condition     = contains(["xsmall", "small", "medium", "large", "xlarge"], var.logscale_cluster_size)
    error_message = "logscale_cluster_size must be one of: xsmall, small, medium, large, or xlarge"
  }
}

variable "logscale_cluster_type" {
  description = "Type of LogScale cluster"
  type        = string
  default     = "basic"
  validation {
    condition     = contains(["basic", "ingress", "internal-ingest"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, ingress, or internal-ingest"
  }
}

# Cluster size definitions
variable "cluster_size_definitions" {
  description = "Cluster size definitions from the template"
  type        = map(any)
}

# Add this to modules/gcp/gke/variables.tf
variable "env_identifier_rand" {
  description = "Random string for environment identification"
  type        = string
}














