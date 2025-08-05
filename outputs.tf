output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "gke_credential_command" {
  description = "Command to get GKE credentials"
  value       = module.gke.gke_credential_command
}

output "logscale_cluster_name" {
  value = var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}"
}

output "logscale_cluster_identifier" {
  value = random_string.env_identifier_rand.result
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

## bastion host outputs

output "bastion_hostname" {
  value = "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bastion"
}

output "bastion_ssh" {
  value = "gcloud compute ssh ${google_compute_instance.bastion[0].name} --project=${var.project_id} --zone=${var.zone}  --tunnel-through-iap"
}

output "bastion_ssh_proxy" {
  value = "gcloud compute ssh ${google_compute_instance.bastion[0].name} --project=${var.project_id} --zone=${var.zone}  --tunnel-through-iap --ssh-flag=\"-4 -L8888:localhost:8888 -N -q -f\""
}

