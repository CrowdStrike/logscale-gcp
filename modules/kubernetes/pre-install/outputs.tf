output "gcp_storage_encryption_key_k8s_secret_name" {
  description = "Name of the Kubernetes secret containing GCP storage encryption key"
  value       = kubernetes_secret.gcp_storage_encryption_key.metadata[0].name
}