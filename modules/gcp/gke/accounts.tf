
# Additional workload identity bindings beyond what the upstream WI module creates.
# Only needed when managing SA lifecycle directly (manage_terraform_service_account = true).
resource "google_service_account_iam_binding" "gcs_wl_binding" {
  count              = var.manage_terraform_service_account ? 1 : 0
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gcs_workload_identity.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  members = concat(
    [
      "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${google_container_cluster.logscale.name}-humio]",
      "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${google_container_cluster.logscale.name}-wl-identity]",
      "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${var.logscale_cluster_k8s_service_account_name}]",
    ],
    []
  )
}


data "google_project" "project" {}

# Terraform Service Account (conditional)
resource "google_service_account" "tf_service_account" {
  count        = var.manage_terraform_service_account ? 1 : 0
  account_id   = (var.logscale_tf_service_account_name != "" ? var.logscale_tf_service_account_name : "${var.infrastructure_prefix}-tf-sa")
  display_name = "Terraform GCP Service Account"
}

resource "google_project_iam_member" "terraform_gcp_sa_storage_admin" {
  count   = var.manage_terraform_service_account ? 1 : 0
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.tf_service_account[0].email}"

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

resource "google_project_iam_member" "terraform_gcp_sa_editor" {
  count   = var.manage_terraform_service_account ? 1 : 0
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.tf_service_account[0].email}"

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

# Cloud services service account editor role
resource "google_project_iam_member" "cloudservices_sa_editor" {
  count   = var.manage_terraform_service_account ? 1 : 0
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${data.google_project.project.number}@cloudservices.gserviceaccount.com"
}

# Container admin role for Kubernetes RBAC operations
resource "google_project_iam_member" "terraform_gcp_sa_container_admin" {
  count   = var.manage_terraform_service_account ? 1 : 0
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.tf_service_account[0].email}"

  depends_on = [
    google_service_account.tf_service_account,
  ]
}

# Security admin role for service account IAM operations
resource "google_project_iam_member" "terraform_gcp_sa_security_admin" {
  count   = var.manage_terraform_service_account ? 1 : 0
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.tf_service_account[0].email}"

  depends_on = [
    google_service_account.tf_service_account,
  ]
}
