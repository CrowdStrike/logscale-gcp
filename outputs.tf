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

# DR-related outputs for remote state access
output "gcs_bucket_id" {
  description = "GCS bucket name for LogScale storage (for remote state access)"
  value       = module.gke.gcs_bucket_id
}

output "gcs_bucket_region" {
  description = "GCS bucket region (for remote state access)"
  value       = module.gke.gcs_bucket_region
}

output "gcs_storage_encryption_key" {
  description = "GCS storage encryption key (primary clusters only)"
  value       = module.kubernetes_post_install.gcp_storage_encryption_key_value
  sensitive   = true
}

output "dr_mode" {
  description = "Current DR mode (active/standby)"
  value       = var.dr
}

output "gce_ingress_ip_address" {
  description = "GCE ingress IP address for DNS configuration"
  value       = module.vpc.gce_ingress_ip_address
}

output "gcs_service_account_email" {
  description = "Service account email for cross-region GCS access"
  value       = module.gke.gcs_service_account_email
}

# DNS failover outputs (primary only)
output "primary_health_check_id" {
  description = "Primary cluster health check ID"
  value       = length(module.dns_failover) > 0 ? module.dns_failover[0].primary_health_check_id : null
}

output "secondary_health_check_id" {
  description = "Secondary cluster health check ID (for secondary reference)"
  value       = length(module.dns_failover) > 0 ? module.dns_failover[0].secondary_health_check_id : null
}

output "global_hostname_fqdn" {
  description = "Global DR hostname FQDN"
  value       = length(module.dns_failover) > 0 ? module.dns_failover[0].global_hostname_fqdn : null
}

# DNS zone output for remote state access
output "global_dns_zone_name" {
  description = "DNS zone name for secondary cluster remote state access"
  value       = local.resolved_dns_zone_name
}

# DR function outputs (secondary only)
output "dr_function_name" {
  description = "DR failover Cloud Function name"
  value       = length(module.dr_failover_function) > 0 ? module.dr_failover_function[0].dr_function_name : null
}

output "dr_pubsub_topic" {
  description = "DR alerts Pub/Sub topic"
  value       = length(module.dr_failover_function) > 0 ? module.dr_failover_function[0].dr_pubsub_topic : null
}

# VPC outputs
output "vpc_network_name" {
  description = "VPC network name"
  value       = module.vpc.network_name
}

output "vpc_subnetwork_name" {
  description = "VPC subnetwork name"
  value       = module.vpc.subnetwork_name
}

# Public DNS FQDN for LogScale cluster
output "public_dns_fqdn" {
  description = "Public DNS FQDN for LogScale cluster (e.g., primary.example.com)"
  value       = length(module.dns_failover) > 0 ? module.dns_failover[0].public_dns_fqdn : null
}

output "nodeport_service_name" {
  description = "NodePort service name for GLB backend configuration"
  value       = module.kubernetes_post_install.nodeport_service_name
}

output "nodeport_service_namespace" {
  description = "NodePort service namespace"
  value       = module.kubernetes_post_install.nodeport_service_namespace
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = var.region
}

output "neg_name" {
  description = "Network Endpoint Group name (computed from service name)"
  value       = "k8s1-${substr(sha256(module.gke.cluster_name), 0, 8)}-${var.logscale_cluster_k8s_namespace_name}-${module.kubernetes_post_install.nodeport_service_name}-8080-${substr(sha256("${module.gke.cluster_name}-${var.logscale_cluster_k8s_namespace_name}-${module.kubernetes_post_install.nodeport_service_name}"), 0, 8)}"
}

output "instance_group_urls" {
  description = "Instance group URLs for the GKE node pools"
  value       = module.gke.instance_group_urls
}

# Global Load Balancer outputs
output "global_lb_ip_address" {
  description = "Global Load Balancer IP address (if enabled)"
  value       = length(module.global_lb) > 0 ? module.global_lb[0].global_ip_address : null
}

output "global_lb_fqdn" {
  description = "Global Load Balancer FQDN (if enabled)"
  value       = length(module.global_lb) > 0 ? module.global_lb[0].global_fqdn : null
}

output "global_lb_backend_service_name" {
  description = "Global Load Balancer backend service name (if enabled)"
  value       = length(module.global_lb) > 0 ? module.global_lb[0].backend_service_name : null
}

output "global_lb_health_check_name" {
  description = "Global Load Balancer health check name (if enabled)"
  value       = length(module.global_lb) > 0 ? module.global_lb[0].health_check_name : null
}

output "global_lb_primary_dns_fqdn" {
  description = "Primary cluster DNS FQDN created by GLB (if enabled)"
  value       = length(module.global_lb) > 0 ? module.global_lb[0].primary_cluster_dns_fqdn : null
}

output "global_lb_secondary_dns_fqdn" {
  description = "Secondary cluster DNS FQDN created by GLB (if enabled)"
  value       = length(module.global_lb) > 0 ? module.global_lb[0].secondary_cluster_dns_fqdn : null
}

# DR standby: surface primary's GLB backend service name from remote state
# Customers use this after standby deploy to register via gcloud
output "primary_glb_backend_service_name" {
  description = "Primary cluster's GLB backend service name (read from remote state, standby only)"
  value       = try(data.terraform_remote_state.primary[0].outputs.global_lb_backend_service_name, null)
}

# Bastion outputs
output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion via IAP tunnel"
  value       = length(module.bastion) > 0 ? module.bastion[0].ssh_command : null
}

output "bastion_proxy_command" {
  description = "SSH command to set up tinyproxy tunnel through the bastion"
  value       = length(module.bastion) > 0 ? module.bastion[0].ssh_proxy_command : null
}

output "bastion_instance_name" {
  description = "Bastion instance name"
  value       = length(module.bastion) > 0 ? module.bastion[0].instance_name : null
}

# Legacy outputs used by LogScale GCP Components
output "logscale_gce_ingress_ip" {
  value = module.vpc.gce_ingress_ip_name
}

output "logscale_cluster_region" {
  value = var.region
}

output "logscale_cluster_zone" {
  value = var.zone
}

output "logscale_cluster_project_id" {
  value = var.project_id
}

