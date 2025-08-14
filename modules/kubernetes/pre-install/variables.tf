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
    condition     = contains(["basic", "ingress", "advanced"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, ingress, or advanced"
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

variable "public_url" {
  description = "Public URL for the cluster"
  type        = string
}

variable "logscale_cluster_name" {
  description = "LogScale cluster name"
  type        = string
}

variable "logscale_gce_ingress_ip" {
  description = "GCE ingress IP name"
  type        = string
}

variable "humiocluster_license" {
  description = "LogScale license key"
  type        = string
  sensitive   = true
}