output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "k8s_configuration_command" {
  description = "Command to get GKE credentials"
  value       = module.gke.gke_credential_command
}

output "k8s_cluster_name" {
  value = var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}"
}

output "logscale_cluster_size" {
  value = var.logscale_cluster_size
}

output "logscale_cluster_type" {
  value = var.logscale_cluster_type
}

output "logscale_cluster_definitions" {
  value = local.cluster_size_rendered
}

output "k8s_cluster_context" {
    value = "gke_${var.project_id}_${var.region}_${module.gke.cluster_name}"
}

output "gke_storage_bucket" {
  value = module.gke.gke_storage_bucket
}

