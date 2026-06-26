# Local Variables
locals {
  # Workspace validation
  current_workspace        = terraform.workspace
  expected_workspace_final = coalesce(var.expected_workspace, "default")

  # Validate workspace matches expected_workspace from tfvars (defaults to "default" if not set)
  workspace_check = local.current_workspace != local.expected_workspace_final ? (
    file("ERROR: Workspace mismatch! Current workspace: '${local.current_workspace}', expected: '${local.expected_workspace_final}'. Please switch to the correct workspace or use the correct tfvars file.")
  ) : null

  # DNS zone name resolution with fallback logic:
  # 1. Try remote state (for secondary clusters reading from primary)
  # 2. Fallback to tfvars variable (for primary clusters or when remote state unavailable)  
  # 3. Validate that we have a real zone name (not placeholder)

  remote_dns_zone_name = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.global_dns_zone_name, "") : ""

  resolved_dns_zone_name = (
    local.remote_dns_zone_name != "" ? local.remote_dns_zone_name :
    var.global_dns_zone_name != "" ? var.global_dns_zone_name :
    ""
  )

  # Render a template of available cluster sizes
  cluster_size_template = jsondecode(templatefile("${path.module}/cluster_size.tpl", {}))
  cluster_size_rendered = {
    for key in keys(local.cluster_size_template) :
    key => local.cluster_size_template[key]
  }
  cluster_size_selected = local.cluster_size_rendered[var.logscale_cluster_size]
  cluster_size          = local.cluster_size_selected
  kubeconfig_filepath   = var.kubeconfig_filepath != "" ? var.kubeconfig_filepath : "${path.root}/kubeconfig"

  # Cluster naming
  logscale_cluster_name = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}")

  # Deterministic secret names — computed here to break the dependency cycle
  # between module.logscale (which reads these) and module.kubernetes_post_install
  # (which creates the secrets in namespace "log" that module.logscale-prereqs creates).
  gcp_encryption_key_secret_name    = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
  gcp_dr_encryption_key_secret_name = var.gcp_recover_from_encryption_key_secret_name
  gcp_dr_encryption_key_secret_key  = var.gcp_recover_from_encryption_key_secret_key

  # Whether this is a DR deployment (has remote state config for cross-cluster discovery)
  is_dr_deployment = var.primary_remote_state_config != null || var.secondary_remote_state_config != null

  # Generate deterministic GCS bucket names
  # DR deployments use dr-primary/dr-secondary prefix for cross-region discovery
  # Non-DR deployments use infrastructure_prefix for neutral naming
  primary_gcs_bucket_name = var.dr_primary_gcs_bucket != "" ? var.dr_primary_gcs_bucket : (
    local.is_dr_deployment ? "dr-primary-${var.region}-${var.project_id}" : "${var.infrastructure_prefix}-${var.region}-${var.project_id}"
  )
  secondary_gcs_bucket_name = local.is_dr_deployment ? "dr-secondary-${var.region}-${var.project_id}" : "${var.infrastructure_prefix}-secondary-${var.region}-${var.project_id}"

  # Determine actual bucket name based on cluster role
  actual_gcs_bucket_name = var.dr == "active" ? local.primary_gcs_bucket_name : local.secondary_gcs_bucket_name

  # Generate deterministic access logs bucket names
  primary_access_logs_bucket_name = var.dr_primary_access_logs_bucket != "" ? var.dr_primary_access_logs_bucket : (
    local.is_dr_deployment ? "logs-pri-${var.region}-${var.project_id}" : "logs-${var.infrastructure_prefix}-${var.region}-${var.project_id}"
  )
  secondary_access_logs_bucket_name = local.is_dr_deployment ? "logs-sec-${var.region}-${var.project_id}" : "logs-${var.infrastructure_prefix}-sec-${var.region}-${var.project_id}"

  # Determine actual access logs bucket name based on cluster role
  actual_access_logs_bucket_name = var.dr == "active" ? local.primary_access_logs_bucket_name : local.secondary_access_logs_bucket_name

  # Remote state and DR recovery configuration
  remote_gcs_encryption_key    = var.primary_remote_state_config == null ? null : try(data.terraform_remote_state.primary[0].outputs.gcs_storage_encryption_key, null)
  effective_gcs_encryption_key = var.existing_gcs_encryption_key != null ? var.existing_gcs_encryption_key : local.remote_gcs_encryption_key

  # IMPORTANT: GCP_RECOVER_FROM_* variables specify WHERE WE ARE RECOVERING FROM (the PRIMARY cluster)
  # NOTE: Variable names use 'gcp_' prefix to match LogScale's environment variable naming (GCP_ prefix).
  # GCP_RECOVER_FROM_BUCKET should be the PRIMARY cluster's bucket (where LogScale will find snapshots)
  # NOTE: GCP_RECOVER_FROM_REGION is not used by LogScale for GCS buckets
  remote_primary_gcs_bucket           = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.gcs_bucket_id, null) : null
  remote_gcp_recover_from_secret_name = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.gcs_encryption_key_secret_name, null) : null

  # DEPRECATED: GCS doesn't use region for bucket access like S3 does
  # Keeping for backwards compatibility with existing tfvars that may reference it
  # remote_primary_gcs_region = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.gcs_bucket_region, null) : null

  # Final values: prefer remote outputs (dynamic), fall back to manually supplied values
  # This prioritizes automation - if remote state has values, use them; otherwise fall back to tfvars
  # DEPRECATED: GCP_RECOVER_FROM_REGION is NOT used by LogScale for GCS buckets
  # final_gcp_recover_from_region = local.remote_primary_gcs_region != null ? local.remote_primary_gcs_region : var.gcp_recover_from_region
  # GCP_RECOVER_FROM_BUCKET: prefer PRIMARY bucket from remote state
  final_gcp_recover_from_bucket = local.remote_primary_gcs_bucket != null ? local.remote_primary_gcs_bucket : var.gcp_recover_from_bucket
  # GCP_RECOVER_FROM_ENCRYPTION_KEY_SECRET_NAME: ALWAYS use the local cluster's secret name
  # The encryption key VALUE comes from primary (via effective_gcs_encryption_key), but the secret NAME is always local
  # Each cluster has its own secret: "${var.logscale_gke_cluster_name}-gcs-storage-encryption"
  final_gcp_recover_from_encryption_key_secret_name = var.gcp_recover_from_encryption_key_secret_name

  # DR recovery replace region configuration
  # This should be in format: <primary-region>/<secondary-region>
  # NOTE: GCP_RECOVER_FROM_REPLACE_REGION IS used for path translation in object keys, even though
  # GCP_RECOVER_FROM_REGION is not used for bucket access. The REPLACE_REGION is for translating
  # paths like "us-west1/bucket/object" to "us-east1/bucket/object" in stored snapshot references.

  # Try to get primary region from remote state for automatic configuration
  remote_primary_gcs_region = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.gcs_bucket_region, null) : null

  # GCP_RECOVER_FROM_REPLACE_REGION: prefer auto-generated from remote state, fall back to tfvars
  # Format: <primary-region>/<secondary-region>
  final_gcp_recover_from_replace_region = (
    var.gcp_recover_from_replace_region != "" ? var.gcp_recover_from_replace_region :
    local.remote_primary_gcs_region != null ? "${local.remote_primary_gcs_region}/${var.region}" :
    ""
  )

  # GCP_RECOVER_FROM_REPLACE_BUCKET: dynamically construct from remote state + local bucket
  # Format: <primary-bucket>/<secondary-bucket>
  # This matches the AWS implementation pattern
  final_gcp_recover_from_replace_bucket = var.gcp_recover_from_replace_bucket != "" ? var.gcp_recover_from_replace_bucket : null

  # DR recovery replace bucket configuration - pull remote cluster name for use in main.tf
  remote_cluster_name = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.cluster_name, null) : null

  # DR peer bucket configuration for cross-region IAM permissions
  # Priority order:
  # 1. Explicitly set dr_primary_gcs_bucket in tfvars (highest priority)
  # 2. Pull from remote state (if primary_remote_state_config is configured)
  # 3. Fall back to gcp_recover_from_bucket from tfvars (lowest priority)
  # This ensures secondary can get primary bucket from remote state OR tfvars
  # Primary cluster must manually specify the secondary bucket in tfvars
  effective_dr_peer_gcs_bucket = coalesce(
    var.dr_primary_gcs_bucket != "" ? var.dr_primary_gcs_bucket : null,
    local.remote_primary_gcs_bucket,
    var.gcp_recover_from_bucket != "" ? var.gcp_recover_from_bucket : null,
    "no-dr-peer-bucket-configured"
  )
}
