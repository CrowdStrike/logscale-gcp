
module "logging_bucket" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = "~> 11.0"
  project_id = var.project_id
  names      = [var.logscale_access_logs_bucket]
  location = var.region
}

module "log_storage_bucket" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = "~> 11.0"
  project_id = var.project_id
  names      = [var.gcs_bucket_name]
  location = var.region
  lifecycle_rules = [{
    
      condition = {
        days_since_noncurrent_time = 1
      }
      action = {
        type = "Delete"
      }
    }
  ]
  logging = {"${var.gcs_bucket_name}" = {
      log_bucket        = module.logging_bucket.name
      log_object_prefix = "access-logs/"
  }
  }

}

# Workload identity for LogScale bucket storage access
module "gcs_workload_identity" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version      = "v38.0.1"
  name         = (var.logscale_cluster_k8s_service_account_name != "" ? var.logscale_cluster_k8s_service_account_name : "${var.infrastructure_prefix}-wl-identity")
  namespace    = var.logscale_cluster_k8s_namespace_name
  project_id   = var.project_id
  cluster_name = google_container_cluster.logscale.name
  roles        = ["roles/storage.admin"]
  automount_service_account_token = true
  annotate_k8s_sa                 = false
  use_existing_k8s_sa             = true
}

# Role for workload identity
resource "google_storage_bucket_iam_member" "members" {
  bucket = module.log_storage_bucket.name
  role   = "roles/storage.objectUser"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}