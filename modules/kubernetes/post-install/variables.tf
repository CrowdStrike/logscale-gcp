# Cluster information
variable "cluster_endpoint" {
  description = "GKE cluster endpoint"
  type        = string
  sensitive   = true
}

variable "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

# LogScale configuration
variable "logscale_cluster_type" {
  description = "Type of LogScale cluster"
  type        = string
  validation {
    condition     = contains(["basic", "dedicated-ui", "advanced"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, dedicated-ui, or advanced"
  }
}

# Project and region
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "logscale_cluster_k8s_namespace_name" {
  description = "Kubernetes namespace for LogScale"
  type        = string
  default     = "log"
}


variable "public_url" {
  description = "Public URL for the cluster"
  type        = string
}

variable "logscale_cluster_name" {
  description = "LogScale cluster name"
  type        = string
}

variable "humio_cluster_instance_name" {
  description = "HumioCluster instance name (for issuer reference)"
  type        = string
}

variable "logscale_gce_ingress_ip" {
  description = "GCE ingress IP name"
  type        = string
}

# GCP-specific ingress variables
variable "enable_gcp_ingress" {
  description = "Enable GCP-specific ingress resources"
  type        = bool
  default     = false
}

variable "gcp_static_ip_name" {
  description = "GCP static IP name for ingress"
  type        = string
  default     = ""
}

variable "gcp_managed_cert_name" {
  description = "GCP managed certificate name"
  type        = string
  default     = ""
}

variable "gcp_ingress_annotations" {
  description = "Custom annotations for GCP ingress"
  type        = map(string)
  default     = {}
}

variable "gcp_service_annotations" {
  description = "Custom annotations for GCP NodePort service"
  type        = map(string)
  default     = {}
}

variable "enable_gke_ingress" {
  description = "Enable GKE native ingress"
  type        = bool
  default     = true
}

variable "enable_nodeport" {
  description = "Enable NodePort service for ingress"
  type        = bool
  default     = true
}

# Cloud-agnostic service and ingress configuration
variable "nodeport_service_annotations" {
  description = "Annotations for the NodePort service"
  type        = map(string)
  default     = {}
}

variable "nodeport_service_selector" {
  description = "Selector for the NodePort service"
  type        = map(string)
  default     = {}
}

variable "gke_ingress_annotations" {
  description = "Annotations for GKE ingress"
  type        = map(string)
  default     = {}
}

# DR Configuration Variables
variable "dr" {
  description = "Disaster Recovery mode: 'active' for primary cluster, 'standby' for secondary cluster"
  type        = string
  default     = "active"
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

variable "gcp_recover_from_encryption_key_secret_name" {
  description = "Kubernetes secret name containing the primary cluster's GCS encryption key (uses gcp_ prefix to match LogScale env var naming)"
  type        = string
  default     = "dr-secondary-gcs-storage-encryption"
}

variable "gcp_recover_from_encryption_key_secret_key" {
  description = "Key within the Kubernetes secret containing the GCS encryption key"
  type        = string
  default     = "gcp-storage-encryption-key"
}

variable "resource_name_prefix" {
  description = "Resource name prefix for creating consistent naming (used for issuer name)"
  type        = string
}

variable "humio_cluster_name_prefix" {
  description = "Full HumioCluster name prefix including random modifier (e.g., z7su31-dr-primary). When set, used for NodePort service selectors to match pod labels. When null, falls back to resource_name_prefix."
  type        = string
  default     = null
}

variable "logscale_ui_nodeport" {
  description = "Fixed NodePort for LogScale UI service (used by Global Load Balancer for DR failover)"
  type        = number
  default     = 31036
}

variable "enable_glb_named_port" {
  description = "Enable named port configuration on instance groups for GLB"
  type        = bool
  default     = false
}

variable "instance_group_urls" {
  description = "List of instance group URLs from GKE node pools"
  type        = list(string)
  default     = []
}

variable "ingress_mode" {
  description = "Per-cluster ingress mode: disabled, internal, external-restricted"
  type        = string
  default     = "disabled"
}

variable "enable_internal_ingress" {
  description = "Enable internal GCE ingress for UI traffic"
  type        = bool
  default     = false
}

variable "cloud_armor_policy_name" {
  description = "Cloud Armor security policy name for BackendConfig (empty = no policy)"
  type        = string
  default     = ""
}

