# modules/gcp/vpc/variables.tf

# Basic configuration
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "infrastructure_prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "logscale"
}

# Network configuration
variable "gcp_network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = ""
}

variable "gcp_subnetwork_name" {
  description = "Name of the subnetwork"
  type        = string
  default     = ""
}

variable "gcp_cidr_range" {
  description = "CIDR range for the main subnetwork"
  type        = string
  default     = "10.128.0.0/20"
}

# Proxy subnetwork (for internal-ingest)
variable "gcp_subnetwork_proxy_name" {
  description = "Name of the proxy subnetwork"
  type        = string
  default     = ""
}

variable "gcp_subnetwork_proxy_cidr_range" {
  description = "CIDR range for the proxy subnetwork"
  type        = string
  default     = "10.129.0.0/20"
}

# LogScale cluster configuration
variable "logscale_cluster_type" {
  description = "Type of LogScale cluster"
  type        = string
  default     = "basic"
  validation {
    condition     = contains(["basic", "ingress", "internal-ingest"], var.logscale_cluster_type)
    error_message = "logscale_cluster_type must be one of: basic, ingress, or internal-ingest"
  }
}

# Static IP names
variable "gce_ingress_ip_name" {
  description = "Name for the GCE ingress IP"
  type        = string
  default     = ""
}

variable "gcp_network_nat_ip_name" {
  description = "Name for the NAT IP"
  type        = string
  default     = ""
}

# Router names
variable "gcp_network_router_name" {
  description = "Name for the network router"
  type        = string
  default     = ""
}

variable "gcp_network_router_nat_name" {
  description = "Name for the router NAT"
  type        = string
  default     = ""
}

# Random identifier
variable "env_identifier_rand" {
  description = "Random string for environment identification"
  type        = string
}
