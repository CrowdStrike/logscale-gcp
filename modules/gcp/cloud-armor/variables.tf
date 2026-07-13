variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "allowed_cidrs" {
  description = "List of CIDR ranges to allow through Cloud Armor"
  type        = list(string)
}
