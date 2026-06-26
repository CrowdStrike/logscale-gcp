# DR Failover Cloud Function Variables

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "cluster_location" {
  description = "GKE cluster location"
  type        = string
}

variable "logscale_namespace" {
  description = "Kubernetes namespace for LogScale"
  type        = string
  default     = "log"
}

variable "target_node_count" {
  description = "Target node count to scale to during DR failover"
  type        = number
  default     = 1
}

variable "function_timeout" {
  description = "Cloud Function timeout in seconds"
  type        = number
  default     = 300
}

variable "function_memory_mb" {
  description = "Cloud Function memory allocation in MB"
  type        = number
  default     = 512
}

variable "dr_enabled" {
  description = "Whether DR failover function should be enabled"
  type        = bool
  default     = false
}

variable "primary_health_check_id" {
  description = "Primary cluster health check ID for monitoring"
  type        = string
  default     = ""
}

variable "secondary_health_check_id" {
  description = "Secondary cluster health check ID for monitoring"
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "Cloud DNS zone name for health check monitoring"
  type        = string
  default     = ""
}

variable "primary_hostname" {
  description = "Primary cluster hostname (e.g., dr-primary)"
  type        = string
  default     = ""
}

variable "secondary_hostname" {
  description = "Secondary cluster hostname (e.g., dr-secondary)"
  type        = string
  default     = ""
}

variable "global_hostname" {
  description = "Global hostname for DR failover"
  type        = string
  default     = ""
}

variable "glb_backend_service_name" {
  description = "Name of the GLB backend service to monitor for health-based failover"
  type        = string
  default     = ""
}

variable "primary_backend_zone" {
  description = "Zone of the primary backend instance group (e.g., us-west1-b)"
  type        = string
  default     = ""
}

variable "enable_glb_health_alert" {
  description = "Enable GLB health-based alerting for DR failover. DEPRECATED: Set to false. The custom GLB backend is not used for actual traffic; use uptime check alerts instead."
  type        = bool
  default     = false
}

variable "humiocluster_name" {
  description = "Name of the HumioCluster CR (used for TLS secret cleanup during failover)"
  type        = string
  default     = ""
}

# =============================================================================
# Retry Configuration
# =============================================================================

variable "max_retries" {
  description = "Maximum number of retry attempts for Kubernetes API calls (retries on HTTP 429, 500, 502, 503, 504 and connection errors)"
  type        = number
  default     = 3

  validation {
    condition     = var.max_retries >= 0 && var.max_retries <= 10
    error_message = "max_retries must be between 0 and 10"
  }
}

variable "base_delay_seconds" {
  description = "Base delay in seconds before first retry (doubles each subsequent attempt with exponential backoff)"
  type        = number
  default     = 1.0

  validation {
    condition     = var.base_delay_seconds >= 0.1 && var.base_delay_seconds <= 10
    error_message = "base_delay_seconds must be between 0.1 and 10"
  }
}

variable "max_delay_seconds" {
  description = "Maximum delay cap in seconds between retries (prevents excessive wait times)"
  type        = number
  default     = 30.0

  validation {
    condition     = var.max_delay_seconds >= 1 && var.max_delay_seconds <= 60
    error_message = "max_delay_seconds must be between 1 and 60"
  }
}

variable "skip_primary_health_validation" {
  description = "Skip primary health check validation; useful for DR simulations where failover should proceed regardless of primary status"
  type        = bool
  default     = false
}

# =============================================================================
# Pre-Failover Validation Configuration
# =============================================================================

variable "pre_failover_failure_seconds" {
  description = "Minimum consecutive seconds the primary must be failing before triggering failover. Set to 0 for immediate failover (testing only)."
  type        = number
  default     = 180

  validation {
    condition     = var.pre_failover_failure_seconds >= 0 && var.pre_failover_failure_seconds <= 600
    error_message = "pre_failover_failure_seconds must be between 0 and 600"
  }
}

variable "failover_cooldown_seconds" {
  description = "Minimum time between failover attempts to prevent flapping (seconds). Set to 0 to disable."
  type        = number
  default     = 300

  validation {
    condition     = var.failover_cooldown_seconds >= 0 && var.failover_cooldown_seconds <= 3600
    error_message = "failover_cooldown_seconds must be between 0 and 3600"
  }
}

variable "dr_function_service_account_email" {
  description = "Email of a pre-existing service account for the DR Cloud Function. When set, skips SA creation (required when org policy blocks SA creation)."
  type        = string
  default     = ""
}

variable "secondary_instance_group_urls" {
  description = "Instance group URLs for the secondary cluster. Passed to Cloud Function for GLB backend registration during failover."
  type        = list(string)
  default     = []
}

# =============================================================================
# Pre-Failover Cleanup Configuration
# =============================================================================

variable "gcs_bucket_name" {
  description = "Standby cluster's GCS bucket name. Used during pre-failover cleanup to remove stale global snapshots that cause Kafka epoch mismatch on boot."
  type        = string
  default     = ""
}

variable "kafka_bootstrap_server" {
  description = "Kafka bootstrap server address (internal to GKE). Used during pre-failover cleanup to delete stale topics before LogScale boots."
  type        = string
  default     = ""
}
