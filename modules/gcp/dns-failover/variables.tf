# DNS Failover Variables

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "dns_zone_name" {
  description = "Cloud DNS zone name"
  type        = string
}

# Global DNS variables (for failover setup - PRIMARY only)
variable "global_hostname" {
  description = "Global hostname for DR failover (e.g., logscale-dr)"
  type        = string
  default     = ""
}

variable "primary_hostname" {
  description = "Primary cluster hostname"
  type        = string
  default     = ""
}

variable "secondary_hostname" {
  description = "Secondary cluster hostname"
  type        = string
  default     = ""
}

# Individual cluster variables (each cluster uses these)
variable "cluster_hostname" {
  description = "This cluster's hostname (for individual A record)"
  type        = string
  default     = ""
}

variable "cluster_ip_address" {
  description = "This cluster's IP address (for individual A record)"
  type        = string
  default     = ""
}

variable "ttl" {
  description = "DNS TTL for failover records"
  type        = number
  default     = 30
}

variable "manage_global_dns" {
  description = "Whether to manage global DNS failover records (PRIMARY only)"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Health check path for DNS failover"
  type        = string
  default     = "/api/v1/status"
}

variable "health_check_port" {
  description = "Health check port for DNS failover"
  type        = number
  default     = 443
}

# Private DNS Configuration (optional internal resolution)
variable "private_dns_zone_name" {
  description = "Optional private Cloud DNS zone name for internal resolution"
  type        = string
  default     = ""
}

# Public DNS Configuration (for external access)
variable "public_dns_zone_name" {
  description = "Public Cloud DNS zone name for external resolution (e.g., my-public-zone)"
  type        = string
  default     = ""
}

variable "public_dns_hostname" {
  description = "Hostname for the public DNS A record (e.g., dr-primary)"
  type        = string
  default     = ""
}

variable "primary_weight" {
  description = "WRR weight for primary endpoint in global DNS failover (0.0-1.0)"
  type        = number
  default     = 1.0
}

variable "secondary_weight" {
  description = "WRR weight for secondary endpoint in global DNS failover (0.0-1.0)"
  type        = number
  default     = 0.0
}

