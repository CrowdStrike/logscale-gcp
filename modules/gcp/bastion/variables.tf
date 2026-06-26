variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone for the bastion instance"
  type        = string
  default     = ""
}

variable "infrastructure_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "network_id" {
  description = "VPC network ID"
  type        = string
}

variable "subnetwork_id" {
  description = "Subnetwork ID for the bastion instance"
  type        = string
}

variable "network_name" {
  description = "VPC network name (for firewall rule)"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type for the bastion"
  type        = string
  default     = "e2-medium"
}

variable "image_type" {
  description = "Boot disk image for the bastion"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "instance_name" {
  description = "Override the bastion instance name (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "service_account_name" {
  description = "Override the bastion SA account_id (auto-generated if empty)"
  type        = string
  default     = ""
}
