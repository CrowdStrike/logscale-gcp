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

# Prefix all resources created
variable "infrastructure_prefix" {
  default = "logscale"
}

# Resource name prefix for LogScale Kubernetes resources (must be short for DNS compliance)
variable "resource_name_prefix" {
  description = "Prefix for LogScale Kubernetes resource names"
  type        = string
  default     = "logscale"

  validation {
    condition     = length(var.resource_name_prefix) <= 8 && can(regex("^[a-z0-9-]*$", var.resource_name_prefix))
    error_message = "Must be 8 or fewer characters (lowercase, numbers, hyphens). Upstream logscale-kubernetes module enforces this limit."
  }
}

# Common labels to apply to all resources
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "A map of tags to apply to resources (mapped to GCP labels)"
  type        = map(string)
  default     = {}
}

# Public URL for LogScale cluster
variable "public_url" {
  description = "Public URL for the LogScale cluster"
  type        = string
}

# LogScale Operator Configuration
variable "humio_operator_chart_version" {
  description = "Humio operator Helm chart version"
  type        = string
}

variable "humio_operator_version" {
  description = "Humio operator version"
  type        = string
}

variable "logscale_image_version" {
  description = "LogScale image version"
  type        = string
}

# Cert-manager Configuration
variable "cm_namespace" {
  description = "Cert-manager namespace"
  type        = string
}

variable "cm_repo" {
  description = "Cert-manager Helm repository"
  type        = string
}

variable "cm_version" {
  description = "Cert-manager version"
  type        = string
}

variable "issuer_kind" {
  description = "Certificate issuer kind"
  type        = string
}

variable "issuer_name" {
  description = "Certificate issuer name"
  type        = string
}

variable "issuer_email" {
  description = "Certificate issuer email"
  type        = string
}

variable "issuer_private_key" {
  description = "Certificate issuer private key"
  type        = string
}

variable "ca_server" {
  description = "Certificate authority server URL"
  type        = string
}

# Strimzi Configuration
variable "strimzi_operator_version" {
  description = "Strimzi operator version"
  type        = string
}

variable "strimzi_operator_chart_version" {
  description = "Strimzi operator chart version"
  type        = string
}

variable "topo_lvm_chart_version" {
  description = "TopoLVM Helm chart version"
  type        = string
  default     = "15.5.2"
}

variable "gateway_api_version" {
  description = "Gateway API helm chart version"
  type        = string
}

# LogScale License
variable "humiocluster_license" {
  description = "LogScale cluster license"
  type        = string
  default     = ""
}

# Humio Operator Extra Values
variable "humio_operator_extra_values" {
  description = "Extra values for Humio operator"
  type        = map(string)
  default     = {}
}

# GCP Region
variable "region" {
  default = "us-central1"
}

# GCP Zone
variable "zone" {
  default = "us-central1-a"
}

# Project ID is unset and must be supplied using -var project_id= or using the _ovverride.tf file
variable "project_id" {
  type = string
}

# GKE minimum master version
variable "min_master_version" {
  default = "1.33.5-gke.1791000"
}


# Nodepool GKE version
variable "node_pool_version" {
  default = "1.33.5-gke.1791000"
}

variable "auto_upgrade" {
  description = "Enable automatic GKE node pool upgrades. When false, node pool version is controlled explicitly via node_pool_version variable."
  type        = bool
  default     = false
}

# Max pods per mode
variable "max_pods_per_node" {
  default = "20"
}

# GKE private nodes
variable "private_nodes" {
  default = "true"
}

# Remove the default node pool
variable "remove_default_node_pool" {
  default = "true"
}

# Node pool auth scopes
variable "node_pool_auth_scopes" {
  type = list(string)

  default = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
  ]
}

# GCP logging service
variable "logging_service" {
  default = "logging.googleapis.com/kubernetes"
}

# GCP Monitoring service
variable "monitoring_service" {
  default = "monitoring.googleapis.com/kubernetes"
}

# Maintenance policy for when auto-update is enabled
variable "maintenance_policy_start_time" {
  default = "05:00"
}

# Enable network policies
variable "network_policy" {
  default = true
}

# Disable VPA
variable "vpa_enabled" {
  default = false
}

# Disable Cloudrun
variable "cloudrun_disabled" {
  default = true
}

# DNS Cache config disabled
variable "dns_cache_config_enabled" {
  default = false
}

# Don't issue client certificate
variable "issue_client_certificate" {
  default = false
}

# Logscale Cluster Name
variable "name" {
  type    = string
  default = "logscale"
}

# Image node pools will use
variable "image_type" {
  type    = string
  default = "COS_CONTAINERD"
}

# Enable shielded nodes
variable "enable_shielded_nodes" {
  type    = bool
  default = true
}

# VPC CIDR
variable "cluster_ipv4_cidr_block" {
  type    = string
  default = "10.0.0.0/14"
}

# GKE Services CIDR
variable "services_ipv4_cidr_block" {
  type    = string
  default = "172.16.1.0/24"
}

# GKE Control plane CIDR 
variable "master_ipv4_cidr_block" {
  type    = string
  default = "172.16.0.0/28"
}

# GCP CIDR range
variable "gcp_cidr_range" {
  type    = string
  default = "10.128.0.0/20"
}

# GCP Subnetwork Proxy Name
variable "gcp_subnetwork_proxy_name" {
  type    = string
  default = ""
}

# GCP Network Router Name
variable "gcp_network_router_name" {
  type    = string
  default = ""
}

# GCP Subnetwork Proxy CIDR Range
variable "gcp_subnetwork_proxy_cidr_range" {
  type    = string
  default = "10.129.0.0/20"
}



# LogScale bucket storage bucket name
variable "gcs_bucket_name" {
  type        = string
  default     = ""
  description = "GCS bucket name for LogScale storage. If empty, will auto-generate shorter name to prevent truncation."
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

# VPC Network Name
variable "gcp_network_name" {
  type    = string
  default = ""
}

# VPC Subnetwork Name
variable "gcp_subnetwork_name" {
  type    = string
  default = ""
}

# LogScale Kubernetes Namespace
variable "logscale_cluster_k8s_namespace_name" {
  default = "log"
  type    = string
}

# Override Terraform Service Account Email
variable "terraform_gcp_sa_email" {
  type    = string
  default = ""
}

# LogScale GKE Cluster Name
variable "logscale_gke_cluster_name" {
  type    = string
  default = ""
}

# Override Terraform Service Account Name
variable "logscale_tf_service_account_name" {
  type    = string
  default = ""
}

# GCE Ingress IP Name
variable "gce_ingress_ip_name" {
  type    = string
  default = ""
}

# VPC NAT IP Name
variable "gcp_network_nat_ip_name" {
  type    = string
  default = ""
}

# VPC Router NAT Name
variable "gcp_network_router_nat_name" {
  type    = string
  default = ""
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

# HumioCluster Instance Name (for certificate issuer reference)
variable "humio_cluster_instance_name" {
  description = "Name of the HumioCluster instance (used for certificate issuer reference)"
  type        = string
  default     = ""
}

# LogScale Cluster Size
variable "logscale_cluster_size" {
  default = "xsmall"
  type    = string
  validation {
    condition     = contains(["xsmall", "small", "medium", "large", "xlarge"], var.logscale_cluster_size)
    error_message = "logscale_cluster_size must be one of: xsmall, small, medium, large, or xlarge"
  }
}

# Remote state where the LogScale GCP Terraform state is stored
# NOTE: This bucket name must also be updated in backend.tf
variable "logscale_gcp_tf_state_bucket" {
  type    = string
  default = "XXXXX-logscale-terraform-state-v1"
}


# true = kubeconfig file on disk (default, works for local dev and automated deployments)
# false = in-line credentials from GKE module (no file dependency, requires cluster to exist)
variable "use_kubeconfig_auth" {
  description = "Use kubeconfig file instead of in-line GKE credentials for Kubernetes auth"
  type        = bool
  default     = true
}

variable "kubeconfig_filepath" {
  description = "Path to kubeconfig file (only used when use_kubeconfig_auth = true)"
  type        = string
  default     = "~/.kube/config"
}

variable "ip_ranges_allowed_to_kubeapi" {
  type        = list(any)
  description = "IP ranges allowed to access the Kubernetes API. When empty, only GCP public CIDRs can reach the API. Add 0.0.0.0/0 for unrestricted access."
  default     = []
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

  validation {
    condition     = contains(["active", "standby"], var.dr)
    error_message = "dr must be either 'active' or 'standby'."
  }
}

variable "dr_use_dedicated_routing" {
  description = <<-EOT
    Enable dedicated pool routing (UI/Ingest pods) for DR clusters.

    Default is true - normal pool-specific routing for optimized traffic distribution.

    Set to false ONLY during DR promotion to enable zero-downtime failover:
    - When false: Service selectors use { "app.kubernetes.io/name" = "humio" } to match ALL pods
    - Traffic continues to existing digest pod while UI/Ingest pods scale up

    Two-phase DR promotion workflow:
    1. First apply: Set dr="active" with dr_use_dedicated_routing=false
       - Zero-downtime: traffic goes to digest pod during UI/Ingest scale-up
    2. Second apply: Set dr_use_dedicated_routing=true (or remove the override)
       - Traffic routes to dedicated UI/Ingest pools

    For non-DR clusters, this variable is ignored - pool-specific routing is always used.
  EOT
  type        = bool
  default     = true
}

variable "primary_remote_state_config" {
  description = "Remote state configuration for accessing primary cluster outputs (used by secondary)"
  type = object({
    backend   = string
    workspace = string
    config    = map(string)
  })
  default = null
}

variable "secondary_remote_state_config" {
  description = "Remote state configuration for accessing secondary cluster outputs (used by primary for GLB)"
  type = object({
    backend   = string
    workspace = string
    config    = map(string)
  })
  default = null
}

variable "dr_primary_gcs_bucket" {
  description = "Primary cluster's GCS bucket name for cross-region access (deterministic naming)"
  type        = string
  default     = ""
}

variable "dr_primary_access_logs_bucket" {
  description = "Primary cluster's access logs bucket name for cross-region access (deterministic naming)"
  type        = string
  default     = ""
}

# GCP DR Recovery Configuration (used by standby clusters)
# NOTE: Variable names use 'gcp_' prefix to match LogScale's environment variable naming (GCP_ prefix).

# DEPRECATED: GCP_RECOVER_FROM_REGION is NOT used by LogScale for GCS buckets.
# GCS does not require region for bucket access.
# Keeping variable for backwards compatibility but it's not passed to LogScale.
variable "gcp_recover_from_region" {
  description = "DEPRECATED: Not used by LogScale for GCS. Primary cluster's GCP region."
  type        = string
  default     = ""
}

variable "gcp_recover_from_bucket" {
  description = "Primary cluster's GCS bucket name for DR recovery"
  type        = string
  default     = ""
}

variable "gcp_recover_from_encryption_key_secret_name" {
  description = "Kubernetes secret name containing the primary cluster's GCS encryption key"
  type        = string
  default     = "gcs-storage-encryption-recovery"
}

variable "gcp_recover_from_encryption_key_secret_key" {
  description = "Key within the Kubernetes secret containing the GCS encryption key"
  type        = string
  default     = "gcp-storage-encryption-key"
}

variable "gcp_recover_from_replace_region" {
  description = "Region replacement pattern for DR recovery (format: old_region/new_region)"
  type        = string
  default     = ""
}

variable "gcp_recover_from_replace_bucket" {
  description = <<-EOT
    GCP_RECOVER_FROM_REPLACE_BUCKET=<primary-cluster>-logscale-storage/<standby-cluster>-logscale-storage

    Only set this variable if there is a copy of the primary bucket data in the
    secondary bucket (e.g. via GCS Transfer Service or dual-region replication).
    If the secondary bucket is empty, LogScale will error with
    ObjectNotInBucketException when looking for historical data in a bucket that
    does not have it. If your secondary bucket is empty, leave this unset —
    LogScale will read historical data from the primary bucket (cross-region,
    readOnly) and write new data to the secondary bucket.
  EOT
  type        = string
  default     = ""
}

# Cloud DNS DR Failover Configuration
variable "manage_global_dns" {
  description = "Whether to manage global DNS failover records (primary only)"
  type        = bool
  default     = true
}

variable "global_dns_zone_name" {
  description = "Cloud DNS zone name for global DR hostname"
  type        = string
  default     = ""
}

variable "global_logscale_hostname" {
  description = "Global hostname for DR failover (e.g., logscale-dr). Must be set explicitly for DR deployments."
  type        = string
  default     = ""
}

variable "primary_logscale_hostname" {
  description = "Primary cluster hostname (e.g., dr-primary). Must be set explicitly for DR deployments."
  type        = string
  default     = ""
}

variable "secondary_logscale_hostname" {
  description = "Secondary cluster hostname (e.g., dr-secondary). Must be set explicitly for DR deployments."
  type        = string
  default     = ""
}

# Optional private DNS for internal resolution of public_url
variable "private_dns_zone_name" {
  description = "Existing private Cloud DNS zone to publish the LogScale ingress A record"
  type        = string
  default     = ""
}

# Public DNS zone for external resolution
variable "public_dns_zone_name" {
  description = "Public Cloud DNS zone name for external resolution. Must be set explicitly for DR deployments."
  type        = string
  default     = ""
}

# DR Cloud Function Configuration
variable "dr_cloud_function_enabled" {
  description = "Enable DR Cloud Function for automated failover (standby only)"
  type        = bool
  default     = false
}

variable "dr_cloud_function_target_node_count" {
  description = "Target node count to scale to during DR failover"
  type        = number
  default     = 1
}

variable "dr_cloud_function_timeout" {
  description = "Cloud Function timeout in seconds"
  type        = number
  default     = 300
}

variable "dr_cloud_function_memory_mb" {
  description = "Cloud Function memory allocation in MB. The failover function loads multiple GCP SDKs (container, monitoring, compute) plus the Kubernetes client, which requires at least 512 MB at runtime."
  type        = number
  default     = 512
}

variable "dr_cloud_function_pre_failover_failure_seconds" {
  description = "Minimum consecutive seconds the primary must be failing before the Cloud Function triggers failover. Set to 0 for immediate failover (testing only). Lower values = faster failover but more susceptible to transient issues."
  type        = number
  default     = 180

  validation {
    condition     = var.dr_cloud_function_pre_failover_failure_seconds >= 0 && var.dr_cloud_function_pre_failover_failure_seconds <= 600
    error_message = "dr_cloud_function_pre_failover_failure_seconds must be between 0 and 600"
  }
}

variable "dr_function_service_account_email" {
  description = "Pre-existing SA email for DR Cloud Function. Skips SA creation when set (required when org policy blocks SA creation)."
  type        = string
  default     = ""
}

variable "dr_glb_backend_service_name" {
  description = "GLB backend service name for health-based DR failover (fallback if remote state unavailable)"
  type        = string
  default     = ""
}

# Existing GCS bucket encryption key variable
variable "existing_gcs_encryption_key" {
  description = "Existing GCS encryption key for standby clusters (alternative to remote state)"
  type        = string
  default     = ""
  sensitive   = true
}

# Terraform workspace validation
variable "expected_workspace" {
  description = "Expected Terraform workspace name for validation (prevents wrong tfvars usage)"
  type        = string
  default     = null

  validation {
    condition     = var.expected_workspace == null || can(regex("^[a-zA-Z0-9_-]+$", var.expected_workspace))
    error_message = "expected_workspace must be a valid workspace name (alphanumeric, hyphens, underscores)"
  }
}

variable "manage_terraform_service_account" {
  description = "Whether to create and manage the Terraform service account and IAM bindings (requires IAM admin permissions)"
  type        = bool
  default     = false
}

# When true (default), no GCP SA is created -- the workload identity module
# looks up existing_gcp_sa_name via data source instead.
variable "use_existing_gcp_sa" {
  description = "Use a pre-existing GCP service account for workload identity instead of creating one"
  type        = bool
  default     = true
}

variable "existing_gcp_sa_name" {
  description = "Full account_id of the pre-existing GCP service account for workload identity. Only used when use_existing_gcp_sa = true."
  type        = string
  default     = ""
}

# Global Load Balancer Configuration
variable "enable_global_lb" {
  description = "Enable Global External Application Load Balancer for health-based DR failover (primary only)"
  type        = bool
  default     = false
}

# Per-cluster Ingress Configuration (independent of GLB)
variable "ingress_mode" {
  description = "Per-cluster ingress mode: disabled (port-forward only), internal (VPC-only GCE LB), external-restricted (external GCE LB + Cloud Armor allowlist)"
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "internal", "external-restricted"], var.ingress_mode)
    error_message = "ingress_mode must be one of: disabled, internal, external-restricted"
  }
}

variable "ingress_allowed_cidrs" {
  description = "CIDR ranges allowed through Cloud Armor (required when ingress_mode is external-restricted)"
  type        = list(string)
  default     = []
}

variable "enable_glb_named_port" {
  description = "Create named port on instance groups for GLB backend (set true on both primary AND secondary clusters when using GLB)"
  type        = bool
  default     = null
}

variable "global_lb_health_check_path" {
  description = "Health check request path for GLB"
  type        = string
  default     = "/api/v1/status"
}

variable "global_lb_health_check_port" {
  description = "Health check port for GLB (must match logscale_ui_nodeport for instance group backends)"
  type        = number
  default     = 31036
}

variable "global_lb_health_check_type" {
  description = "Health check type for GLB: HTTP (for kubelet healthz on port 10256), HTTPS (for LogScale endpoint), or TCP (port availability check)"
  type        = string
  default     = "TCP"
  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.global_lb_health_check_type)
    error_message = "global_lb_health_check_type must be 'HTTP', 'HTTPS', or 'TCP'."
  }
}

variable "global_lb_primary_capacity" {
  description = "Capacity scaler for primary backend (1.0 = full capacity)"
  type        = number
  default     = 1.0
}

variable "global_lb_primary_neg_self_link" {
  description = "Primary NEG self link for GLB (preferred over instance group when provided)"
  type        = string
  default     = ""
}

variable "global_lb_secondary_neg_self_link" {
  description = "Secondary NEG self link for GLB (preferred over instance group when provided)"
  type        = string
  default     = ""
}

variable "global_lb_secondary_capacity" {
  description = "Capacity scaler for secondary backend (0.0 = failover only)"
  type        = number
  default     = 0.0
}

variable "global_lb_create_cluster_dns" {
  description = "Create per-cluster DNS A records via GLB module (dr-primary, dr-secondary)"
  type        = bool
  default     = true
}

variable "global_lb_secondary_cluster_ip" {
  description = "Secondary cluster's static IP address for DNS A record (required if global_lb_create_cluster_dns=true)"
  type        = string
  default     = ""
}

variable "glb_backend_port" {
  description = "Backend port for Global Load Balancer - must match logscale_ui_nodeport"
  type        = number
  default     = 31036
}

variable "logscale_ui_nodeport" {
  description = "Fixed NodePort for LogScale UI service (used by Global Load Balancer for DR failover)"
  type        = number
  default     = 31036
}

# GCP uses Google Managed Certificates for ingress TLS by default.
# Set to false to install cert-manager instead, which is required when
# TopoLVM is enabled (its webhook needs cert-manager for TLS certs).
variable "use_own_certificate_for_ingress" {
  description = "Use GCP-managed certs for ingress instead of cert-manager. Set false when TopoLVM needs cert-manager for webhook TLS."
  type        = bool
  default     = true
}

# ── Bastion ──────────────────────────────────────────────────────────────────

variable "bastion_host_enabled" {
  description = "Create a bastion host for SSH access to the private GKE cluster via IAP"
  type        = bool
  default     = false
}

variable "bastion_machine_type" {
  description = "GCE machine type for the bastion instance"
  type        = string
  default     = "e2-medium"
}

variable "bastion_image_type" {
  description = "Boot disk image for the bastion instance"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "bastion_instance_name" {
  description = "Override the bastion instance name (auto-generated from infrastructure_prefix if empty)"
  type        = string
  default     = ""
}

variable "bastion_service_account_name" {
  description = "Override the bastion service account ID (auto-generated if empty)"
  type        = string
  default     = ""
}
