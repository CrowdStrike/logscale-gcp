
# Access logs bucket
module "logging_bucket" {
  source        = "terraform-google-modules/cloud-storage/google"
  version       = "~> 11.0"
  project_id    = var.project_id
  names         = [var.logscale_access_logs_bucket]
  location      = var.region
  force_destroy = { (var.logscale_access_logs_bucket) = var.gcs_force_destroy }
}

# Main LogScale data storage bucket
module "log_storage_bucket" {
  source        = "terraform-google-modules/cloud-storage/google"
  version       = "~> 11.0"
  project_id    = var.project_id
  names         = [var.gcs_bucket_name]
  location      = var.region
  force_destroy = { (var.gcs_bucket_name) = var.gcs_force_destroy }

  lifecycle_rules = [{
    condition = {
      days_since_noncurrent_time = 1
    }
    action = {
      type = "Delete"
    }
  }]

  logging = { "${var.gcs_bucket_name}" = {
    log_bucket        = module.logging_bucket.name
    log_object_prefix = "access-logs/"
  } }
}

# Workload identity for LogScale bucket storage access
module "gcs_workload_identity" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version = "v38.0.1"
  name    = (var.logscale_cluster_k8s_service_account_name != "" ? var.logscale_cluster_k8s_service_account_name : "${var.infrastructure_prefix}-wl-identity")
  # Override the GCP SA lookup name when using a pre-existing SA
  gcp_sa_name                     = var.use_existing_gcp_sa && var.existing_gcp_sa_name != "" ? var.existing_gcp_sa_name : null
  namespace                       = var.logscale_cluster_k8s_namespace_name
  project_id                      = var.project_id
  cluster_name                    = google_container_cluster.logscale.name
  roles                           = ["roles/storage.admin"]
  automount_service_account_token = true
  # K8s SA annotation is handled by the LogScale operator, not Terraform
  annotate_k8s_sa = false
  # K8s SA is created by the LogScale operator/Helm, not by this module
  use_existing_k8s_sa = true
  # When true, looks up an existing GCP SA via data source instead of creating one
  use_existing_gcp_sa = var.use_existing_gcp_sa
}

# Role for workload identity
resource "google_storage_bucket_iam_member" "members" {
  bucket = module.log_storage_bucket.name
  role   = "roles/storage.objectUser"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}

# Role for workload identity - access logs bucket
resource "google_storage_bucket_iam_member" "access_logs_bucket_permissions" {
  bucket = module.logging_bucket.name
  role   = "roles/storage.objectUser"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}

# DR cross-region bucket access permissions (for standby clusters)
# This allows the secondary cluster to read from the primary cluster's bucket
resource "google_storage_bucket_iam_member" "dr_cross_region_access" {
  count  = var.dr == "standby" && var.dr_primary_gcs_bucket != "" ? 1 : 0
  bucket = var.dr_primary_gcs_bucket
  role   = "roles/storage.legacyBucketReader"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}

resource "google_storage_bucket_iam_member" "dr_cross_region_object_access" {
  count  = var.dr == "standby" && var.dr_primary_gcs_bucket != "" ? 1 : 0
  bucket = var.dr_primary_gcs_bucket
  role   = "roles/storage.objectViewer"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}
