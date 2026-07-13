# Remote state data source for secondary clusters to access primary outputs
data "terraform_remote_state" "primary" {
  count   = var.primary_remote_state_config != null ? 1 : 0
  backend = var.primary_remote_state_config.backend

  workspace = var.primary_remote_state_config.workspace
  config    = var.primary_remote_state_config.config
}

# Remote state data source for primary cluster to access secondary outputs (for GLB)
# This allows primary to automatically discover secondary's instance group and IP
data "terraform_remote_state" "secondary" {
  count   = var.secondary_remote_state_config != null ? 1 : 0
  backend = var.secondary_remote_state_config.backend

  workspace = var.secondary_remote_state_config.workspace
  config    = var.secondary_remote_state_config.config
}

# Fetch the DNS managed zone using resolved zone name with fallback logic
data "google_dns_managed_zone" "env_dns_zone" {
  count   = local.resolved_dns_zone_name != "" ? 1 : 0
  name    = local.resolved_dns_zone_name
  project = var.project_id

  lifecycle {
    precondition {
      condition     = local.resolved_dns_zone_name != ""
      error_message = "DNS zone name must be provided via 'global_dns_zone_name' in tfvars or be available in remote terraform state."
    }
  }
}
