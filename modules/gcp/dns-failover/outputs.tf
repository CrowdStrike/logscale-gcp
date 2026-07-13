output "dns_zone_name" {
  description = "DNS zone name"
  value       = local.create_global_dns_resources ? data.google_dns_managed_zone.dns_zone.name : null
}

output "dns_zone_dns_name" {
  description = "DNS zone DNS name"
  value       = local.create_global_dns_resources ? data.google_dns_managed_zone.dns_zone.dns_name : null
}

output "primary_health_check_id" {
  description = "Primary cluster health check ID"
  value       = local.create_global_dns_resources ? google_compute_health_check.primary_health_check[0].id : null
}

output "secondary_health_check_id" {
  description = "Secondary cluster health check ID"
  value       = local.create_global_dns_resources ? google_compute_health_check.secondary_health_check[0].id : null
}

output "global_hostname_fqdn" {
  description = "Fully qualified domain name for global DR hostname"
  value       = local.create_global_dns_resources ? "${var.global_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}" : null
}

output "primary_hostname_fqdn" {
  description = "Fully qualified domain name for primary cluster"
  value       = local.create_global_dns_resources ? "${var.primary_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}" : null
}

output "secondary_hostname_fqdn" {
  description = "Fully qualified domain name for secondary cluster"
  value       = local.create_global_dns_resources ? "${var.secondary_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}" : null
}

output "public_dns_fqdn" {
  description = "Fully qualified domain name for public DNS record (e.g., primary.example.com)"
  value       = local.create_public_dns_record ? "${var.public_dns_hostname}.${data.google_dns_managed_zone.public_dns_zone[0].dns_name}" : null
}

output "public_dns_zone_name" {
  description = "Public DNS zone name"
  value       = local.create_public_dns_record ? data.google_dns_managed_zone.public_dns_zone[0].name : null
}