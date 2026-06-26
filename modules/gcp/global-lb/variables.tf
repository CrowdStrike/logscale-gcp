variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "global_hostname" {
  description = "Global hostname for the load balancer (e.g., dr-logscale.example.com)"
  type        = string
}

variable "dns_zone_name" {
  description = "Cloud DNS zone name for DNS record creation"
  type        = string
}

variable "primary_neg_self_link" {
  description = "Self link of the primary cluster's Network Endpoint Group"
  type        = string
  default     = ""
}

variable "secondary_neg_self_link" {
  description = "Self link of the secondary cluster's Network Endpoint Group"
  type        = string
  default     = ""
}

variable "primary_instance_group" {
  description = "Primary cluster's instance group URL(s) — one per zone for regional GKE clusters"
  type        = list(string)
  default     = []
}

variable "secondary_instance_group" {
  description = "Secondary cluster's instance group URL(s) — one per zone for regional GKE clusters"
  type        = list(string)
  default     = []
}

variable "primary_region" {
  description = "Primary cluster region"
  type        = string
}

variable "secondary_region" {
  description = "Secondary cluster region"
  type        = string
}

variable "health_check_path" {
  description = "Health check request path (used for HTTPS health checks)"
  type        = string
  default     = "/api/v1/status"
}

variable "health_check_port" {
  description = "Health check port"
  type        = number
  default     = 443
}

variable "health_check_type" {
  description = "Health check type: HTTP (for kubelet healthz), HTTPS (for LogScale endpoint), or TCP (for port availability)"
  type        = string
  default     = "HTTPS"
  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.health_check_type)
    error_message = "health_check_type must be 'HTTP', 'HTTPS', or 'TCP'."
  }
}

variable "health_check_interval_sec" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
}

variable "health_check_timeout_sec" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Number of consecutive successes before marking healthy"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failures before marking unhealthy"
  type        = number
  default     = 3
}

variable "primary_capacity_scaler" {
  description = "Capacity scaler for primary backend (1.0 = full capacity, 0.0 = no traffic)"
  type        = number
  default     = 1.0
}

variable "secondary_capacity_scaler" {
  description = "Capacity scaler for secondary backend (0.0 = failover only)"
  type        = number
  default     = 0.0
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for the backend service"
  type        = bool
  default     = false
}

variable "ssl_policy" {
  description = "SSL policy name (optional)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "connection_draining_timeout_sec" {
  description = "Connection draining timeout in seconds"
  type        = number
  default     = 300
}

variable "enable_logging" {
  description = "Enable logging for the backend service"
  type        = bool
  default     = true
}

variable "log_sample_rate" {
  description = "Sample rate for logging (0.0 to 1.0)"
  type        = number
  default     = 1.0
}

variable "create_cluster_dns_records" {
  description = "Create per-cluster DNS A records (primary and secondary)"
  type        = bool
  default     = false
}

variable "primary_cluster_hostname" {
  description = "Primary cluster hostname (e.g., dr-primary)"
  type        = string
  default     = ""
}

variable "secondary_cluster_hostname" {
  description = "Secondary cluster hostname (e.g., dr-secondary)"
  type        = string
  default     = ""
}

variable "primary_cluster_ip" {
  description = "Primary cluster's static IP address for DNS A record"
  type        = string
  default     = ""
}

variable "secondary_cluster_ip" {
  description = "Secondary cluster's static IP address for DNS A record"
  type        = string
  default     = ""
}

variable "dns_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 30
}

variable "public_dns_zone_name" {
  description = "Public DNS zone name for external resolution (optional)"
  type        = string
  default     = ""
}

variable "create_public_dns_records" {
  description = "Create DNS records in public zone"
  type        = bool
  default     = false
}
