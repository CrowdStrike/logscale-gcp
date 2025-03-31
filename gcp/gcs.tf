# GCS Buckets


#Bucket used for logging
resource "google_storage_bucket" "log_bucket" {
  name = (var.logscale_access_logs_bucket != "" ? var.logscale_access_logs_bucket : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-logs")

  # should this move to region?
  location = "US"
}

locals {
  logscale_cluster_name = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}")
}

resource "google_storage_bucket" "logscale_bucket_storage" {
  name     = (var.gcs_bucket_name != "" ? var.gcs_bucket_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bucket-storage")
  location = var.region

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 1
    }
    action {
      type = "Delete"
    }
  }

  logging {
    log_bucket        = google_storage_bucket.log_bucket.name
    log_object_prefix = "access-logs/"
  }
}

# Workload identity for LogScale bucket storage access
module "gcs_workload_identity" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  name         = (var.logscale_cluster_k8s_service_account_name != "" ? var.logscale_cluster_k8s_service_account_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-wl-identity")
  namespace    = var.logscale_cluster_k8s_namespace_name
  project_id   = var.project_id
  cluster_name = google_container_cluster.logscale_test1.name

  automount_service_account_token = true
  annotate_k8s_sa                 = false
  use_existing_k8s_sa             = true
}

# Role for workload identity
resource "google_storage_bucket_iam_member" "members" {
  bucket = google_storage_bucket.logscale_bucket_storage.name
  role   = "roles/storage.objectUser"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}

# Binding for service accounts
resource "google_service_account_iam_binding" "gcs_wl_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gcs_workload_identity.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${local.logscale_cluster_name}-humio]",
    "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${local.logscale_cluster_name}-wl-identity]",
  ]
}
