
# Binding for service accounts - infrastructure level only, LogScale app service accounts handled in main.tf
resource "google_service_account_iam_binding" "gcs_wl_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gcs_workload_identity.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${google_container_cluster.logscale.name}-wl-identity]",
  ]
}

data "google_project" "project" {}

# Terraform Service Account
resource "google_service_account" "tf_service_account" {
  account_id   = (var.logscale_tf_service_account_name != "" ? var.logscale_tf_service_account_name : "${var.infrastructure_prefix}-tf-sa")
  display_name = "Terraform GCP Service Account"
}

# Terraform service account roles
resource "google_project_iam_binding" "terraform_gcp_sa_roles" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

# Cloudservices and Terraform service account binding
resource "google_project_iam_binding" "terraform_gcp_sa_editor" {
  project = var.project_id
  role    = "roles/editor"
  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}",
    "serviceAccount:${data.google_project.project.number}@cloudservices.gserviceaccount.com"
  ]

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

# Container admin role for Kubernetes RBAC operations (roles, rolebindings, etc.)
resource "google_project_iam_binding" "terraform_gcp_sa_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

# Security admin role for service account IAM operations
resource "google_project_iam_binding" "terraform_gcp_sa_security_admin" {
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

