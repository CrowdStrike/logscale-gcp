output "gcp_storage_encryption_key_k8s_secret_name" {
  description = "Name of the Kubernetes secret containing GCP storage encryption key"
  value       = kubernetes_secret.gcp_storage_encryption_key.metadata[0].name
}

output "gcp_storage_encryption_key_value" {
  description = "GCP storage encryption key value (for remote state access)"
  value       = kubernetes_secret.gcp_storage_encryption_key.data["gcp-storage-encryption-key"]
  sensitive   = true
}

output "gcp_dr_storage_encryption_key_k8s_secret_name" {
  description = "Name of the Kubernetes secret containing the primary's GCS encryption key for DR recovery"
  value       = local.dr_resolved_encryption_key != "" ? kubernetes_secret.gcp_dr_storage_encryption_key[0].metadata[0].name : null
}

output "gcp_dr_storage_encryption_key_k8s_secret_key" {
  description = "Key within the Kubernetes secret containing the GCS encryption key for DR recovery"
  value       = var.gcp_recover_from_encryption_key_secret_key != "" ? var.gcp_recover_from_encryption_key_secret_key : "gcp-storage-encryption-key"
}

output "nodeport_service_name" {
  description = "Name of the NodePort service for external ingress"
  value       = kubernetes_service.logscale_nodeport.metadata[0].name
}

output "nodeport_service_namespace" {
  description = "Namespace of the NodePort service"
  value       = kubernetes_service.logscale_nodeport.metadata[0].namespace
}

output "nodeport_service_port" {
  description = "NodePort number assigned to the LogScale service"
  value       = kubernetes_service.logscale_nodeport.spec[0].port[0].node_port
}