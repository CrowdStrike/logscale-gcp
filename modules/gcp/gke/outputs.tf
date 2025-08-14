output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.logscale.name
}

output "cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.logscale.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate of the GKE cluster"
  value       = google_container_cluster.logscale.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.logscale.location
}

output "node_pools" {
  description = "Node pool information"
  value = {
    logscale_node_pool = {
      name = google_container_node_pool.logscale_node_pool.name
    }
    ingress_node_pool = length(google_container_node_pool.logscale_ingress_node_pool) > 0 ? {
      name = google_container_node_pool.logscale_ingress_node_pool[0].name
    } : null
    ingest_node_pool = length(google_container_node_pool.logscale_ingest_node_pool) > 0 ? {
      name = google_container_node_pool.logscale_ingest_node_pool[0].name
    } : null
    ui_node_pool = length(google_container_node_pool.logscale_ui_node_pool) > 0 ? {
      name = google_container_node_pool.logscale_ui_node_pool[0].name
    } : null
  }
}

output "gke_credential_command" {
  description = "Command to get GKE credentials"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.logscale.name} --region ${var.region} --project ${var.project_id}"
}
