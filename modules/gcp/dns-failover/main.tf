# DNS Failover Module for GCP DR Setup
# Alternative to GLB-based failover — uses Cloud DNS WRR routing policy.
# Mutually exclusive with module.global_lb (gated by !enable_global_lb).
# Failover requires manual weight change via TF variables (no auto-trigger).
# STATUS: EXPERIMENTAL — not yet validated in production.
# - Each cluster creates its own individual A record
# - Only PRIMARY cluster creates global DNS failover records pointing to individual FQDNs

locals {
  # Build FQDNs for primary and secondary clusters
  primary_ingest_fqdn = (
    var.primary_hostname != "" ?
    "${var.primary_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}" :
    null
  )

  secondary_ingest_fqdn = (
    var.secondary_hostname != "" ?
    "${var.secondary_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}" :
    null
  )

  global_ingest_fqdn = (
    var.global_hostname != "" ?
    "${var.global_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}" :
    null
  )

  # Only create global DNS resources if managing global DNS (primary only)
  create_global_dns_resources = var.manage_global_dns && var.dns_zone_name != ""

  # Create individual DNS record if we have the required parameters
  create_individual_record = var.dns_zone_name != "" && var.cluster_hostname != "" && var.cluster_ip_address != ""

  # Create public DNS record if public zone is configured
  create_public_dns_record = var.public_dns_zone_name != "" && var.public_dns_hostname != "" && var.cluster_ip_address != ""
}

# Get the DNS zone
data "google_dns_managed_zone" "dns_zone" {
  name = var.dns_zone_name
}

# Get the public DNS zone (if configured)
data "google_dns_managed_zone" "public_dns_zone" {
  count = local.create_public_dns_record ? 1 : 0
  name  = var.public_dns_zone_name
}

# Individual cluster A record (each cluster creates its own)
resource "google_dns_record_set" "cluster_record" {
  count = local.create_individual_record ? 1 : 0

  name         = "${var.cluster_hostname}.${data.google_dns_managed_zone.dns_zone.dns_name}"
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  type         = "A"
  ttl          = var.ttl

  rrdatas = [var.cluster_ip_address]
}

# Health check for primary cluster — used by Cloud DNS routing policy for failover
resource "google_compute_health_check" "primary_health_check" {
  count = local.create_global_dns_resources ? 1 : 0
  name  = "${var.primary_hostname}-health-check"

  timeout_sec         = 10
  check_interval_sec  = 30
  healthy_threshold   = 1
  unhealthy_threshold = 3

  https_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
    host         = var.primary_hostname
  }
}

# Health check for secondary cluster — used by Cloud DNS routing policy for failover
resource "google_compute_health_check" "secondary_health_check" {
  count = local.create_global_dns_resources ? 1 : 0
  name  = "${var.secondary_hostname}-health-check"

  timeout_sec         = 10
  check_interval_sec  = 30
  healthy_threshold   = 1
  unhealthy_threshold = 3

  https_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
    host         = var.secondary_hostname
  }
}

# Global DNS failover record (PRIMARY only - single record with multiple WRR policies)
resource "google_dns_record_set" "global_failover" {
  count = local.create_global_dns_resources ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.global_ingest_fqdn != null && local.primary_ingest_fqdn != null && local.secondary_ingest_fqdn != null && var.dns_zone_name != ""
      error_message = "manage_global_dns=true requires global_hostname, primary_hostname, secondary_hostname, and dns_zone_name to be non-empty."
    }
  }

  name         = local.global_ingest_fqdn
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  type         = "CNAME"
  ttl          = var.ttl

  routing_policy {
    wrr {
      weight  = var.primary_weight
      rrdatas = [local.primary_ingest_fqdn]
    }

    wrr {
      weight  = var.secondary_weight
      rrdatas = [local.secondary_ingest_fqdn]
    }
  }
}

# Public DNS A record for external access (e.g., primary.example.com)
resource "google_dns_record_set" "public_cluster_record" {
  count = local.create_public_dns_record ? 1 : 0

  name         = "${var.public_dns_hostname}.${data.google_dns_managed_zone.public_dns_zone[0].dns_name}"
  managed_zone = data.google_dns_managed_zone.public_dns_zone[0].name
  type         = "A"
  ttl          = var.ttl

  rrdatas = [var.cluster_ip_address]
}