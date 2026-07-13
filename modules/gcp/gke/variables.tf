variable "deletion_protection" {
  description = "Prevent accidental cluster deletion."
  type        = bool
  default     = true
}

variable "gcs_force_destroy" {
  description = "Allow Terraform to destroy GCS buckets even when they contain objects"
  type        = bool
  default     = false
}

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
  default     = "1.33.3-gke.1136000"
}

variable "node_pool_version" {
  description = "GKE node pool version. Should match min_master_version. When auto_upgrade=true, this is the initial version only — GKE will auto-upgrade within the maintenance window. When auto_upgrade=false, this is the pinned version and must be updated manually."
  type        = string
  default     = "1.33.3-gke.1136000"
}

variable "auto_upgrade" {
  description = "Enable automatic node pool version upgrades. Set to false (default) for manual control over node pool versions via node_pool_version variable. Set to true to let GKE auto-upgrade node pools to match the control plane version within the maintenance window."
  type        = bool
  default     = false
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

# LogScale Cluster Type
variable "logscale_cluster_type" {
  description = "Logscale cluster type"
  type        = string

  validation {
    condition     = contains(["basic", "dedicated-ui", "advanced"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, dedicated-ui, or advanced"
  }
}

# Cluster size definitions
variable "cluster_size_definitions" {
  description = "Cluster size definitions from the template"
  type        = map(any)
}

variable "ip_ranges_allowed_to_kubeapi" {
  type        = list(any)
  description = "IP ranges allowed to access the Kubernetes API. When empty, only GCP public CIDRs can reach the API. Add 0.0.0.0/0 for unrestricted access."
  default     = []
}

# LogScale bucket storage bucket name
variable "gcs_bucket_name" {
  type = string
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

# LogScale Kubernetes Namespace
variable "logscale_cluster_k8s_namespace_name" {
  default = "logging"
  type    = string
}

# Override Terraform Service Account Name
variable "logscale_tf_service_account_name" {
  type    = string
  default = ""
}

variable "kubernetes_private_cluster_enabled" {
  type        = bool
  default     = false
  description = "When true, the kubernetes API is only accessible from internal networks. When false, the API is available to the list of IP ranges provided in variable ip_ranges_allowed_to_kubeapi."
}

variable "provision_kafka_servers" {
  description = "Set this to true to provision strimzi kafka within this kubernetes cluster. It should be false if you are bringing your own kafka implementation."
  default     = true
  type        = bool
}

# DR Configuration Variables
variable "dr" {
  description = "Disaster Recovery mode: 'active' for primary cluster, 'standby' for secondary cluster"
  type        = string
  default     = "active"
}

variable "dr_primary_gcs_bucket" {
  description = "Primary cluster's GCS bucket name for cross-region access"
  type        = string
  default     = ""
}

variable "manage_terraform_service_account" {
  description = "Whether to create and manage the Terraform service account and IAM bindings (requires IAM admin permissions)"
  type        = bool
  default     = false
}

# When use_existing_gcp_sa = true (default), the workload identity module
# looks up an already-provisioned GCP SA via data source. The caller must
# supply the full account_id via existing_gcp_sa_name.
# When false, the module creates a new SA using infrastructure_prefix naming.
variable "use_existing_gcp_sa" {
  description = "Use a pre-existing GCP service account for workload identity instead of creating one"
  type        = bool
  default     = true
}

variable "existing_gcp_sa_name" {
  description = "Full account_id of the pre-existing GCP service account for workload identity (e.g. 'my-project-tf-sa'). Only used when use_existing_gcp_sa = true."
  type        = string
  default     = ""
}

variable "primary_remote_state" {
  description = "Primary cluster's remote state data (for secondary clusters)"
  type        = any
  default     = null
}

variable "existing_gcs_encryption_key" {
  description = "Existing GCS encryption key for standby clusters"
  type        = string
  default     = ""
  sensitive   = true
}

variable "resource_name_prefix" {
  description = "Prefix used for LogScale resources (HumioCluster name)"
  type        = string
  default     = ""
}

variable "logscale_cluster_name_prefix" {
  description = "Full cluster name prefix from logscale module (includes random prefix, e.g., z7su31-dr-primary). Used for node pool SA workload identity bindings."
  type        = string
  default     = ""
}

# IAM binding toggles for the terraform service account
variable "logscale_tf_service_account_iam_storage_admin_enabled" {
  description = "Enable storage.admin IAM binding for the terraform service account"
  type        = bool
  default     = true
}

variable "logscale_tf_service_account_iam_compute_admin_enabled" {
  description = "Enable compute.admin IAM binding for the terraform service account"
  type        = bool
  default     = true
}

variable "logscale_tf_service_account_iam_gke_admin_enabled" {
  description = "Enable container.admin IAM binding for the terraform service account"
  type        = bool
  default     = true
}
