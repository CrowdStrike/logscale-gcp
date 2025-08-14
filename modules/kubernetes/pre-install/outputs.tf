output "gcp_storage_encryption_key_k8s_secret_name" {
  description = "Name of the Kubernetes secret containing GCP storage encryption key"
  value       = kubernetes_secret.gcp_storage_encryption_key.metadata[0].name
}

output "humiocluster_license_k8s_secret_name" {
  description = "Name of the Kubernetes secret containing Humio license"
  value       = kubernetes_secret.humiocluster_license.metadata[0].name
}

output "static_user_logins_k8s_secret_name" {
  description = "Name of the Kubernetes secret containing static user logins"
  value       = kubernetes_secret.static_user_logins.metadata[0].name
}