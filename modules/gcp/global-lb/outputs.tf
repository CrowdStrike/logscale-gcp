output "global_ip_address" {
  description = "Global load balancer IP address"
  value       = google_compute_global_address.global_ip.address
}

output "global_ip_name" {
  description = "Global load balancer IP name"
  value       = google_compute_global_address.global_ip.name
}

output "global_fqdn" {
  description = "Fully qualified domain name for the global endpoint"
  value       = local.global_fqdn
}

output "backend_service_id" {
  description = "Backend service ID"
  value       = google_compute_backend_service.logscale.id
}

output "backend_service_name" {
  description = "Backend service name"
  value       = google_compute_backend_service.logscale.name
}

output "health_check_id" {
  description = "Health check ID"
  value       = google_compute_health_check.logscale.id
}

output "health_check_name" {
  description = "Health check name"
  value       = google_compute_health_check.logscale.name
}

output "ssl_certificate_id" {
  description = "SSL certificate ID"
  value       = google_compute_managed_ssl_certificate.logscale.id
}

output "url_map_id" {
  description = "URL map ID"
  value       = google_compute_url_map.logscale.id
}

output "https_proxy_id" {
  description = "HTTPS proxy ID"
  value       = google_compute_target_https_proxy.logscale.id
}

output "dns_record_name" {
  description = "DNS record name"
  value       = google_dns_record_set.global.name
}

output "primary_cluster_dns_fqdn" {
  description = "Primary cluster DNS FQDN"
  value       = length(google_dns_record_set.primary_cluster) > 0 ? trimsuffix(google_dns_record_set.primary_cluster[0].name, ".") : null
}

output "secondary_cluster_dns_fqdn" {
  description = "Secondary cluster DNS FQDN"
  value       = length(google_dns_record_set.secondary_cluster) > 0 ? trimsuffix(google_dns_record_set.secondary_cluster[0].name, ".") : null
}

output "public_primary_dns_fqdn" {
  description = "Public DNS FQDN for primary cluster"
  value       = length(google_dns_record_set.public_primary) > 0 ? trimsuffix(google_dns_record_set.public_primary[0].name, ".") : null
}

output "public_secondary_dns_fqdn" {
  description = "Public DNS FQDN for secondary cluster"
  value       = length(google_dns_record_set.public_secondary) > 0 ? trimsuffix(google_dns_record_set.public_secondary[0].name, ".") : null
}

output "public_global_dns_fqdn" {
  description = "Public DNS FQDN for global endpoint"
  value       = length(google_dns_record_set.public_global) > 0 ? trimsuffix(google_dns_record_set.public_global[0].name, ".") : null
}
