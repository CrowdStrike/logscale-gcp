data "google_project" "project" {}

# Terraform Service Account
resource "google_service_account" "tf_service_account" {
  account_id   = (var.logscale_tf_service_account_name != "" ? var.logscale_tf_service_account_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-tf-sa")
  display_name = "Terraform GCP Service Account"
}

# Bastion Service Account
resource "google_service_account" "bastion_service_account" {
  count = var.bastion_host_enabled ? 1 : 0 
  account_id   = (var.logscale_bastion_sa_name != "" ? var.logscale_bastion_sa_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bastion-sa")
  display_name = "SA for Bastion VM Instance"
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