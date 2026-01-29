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
  default     = "logging"
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace"
  type        = bool
  default     = true
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

