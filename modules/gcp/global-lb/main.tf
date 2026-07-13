locals {
  use_neg     = var.primary_neg_self_link != "" || var.secondary_neg_self_link != ""
  dns_zone    = data.google_dns_managed_zone.zone.dns_name
  global_fqdn = "${var.global_hostname}.${trimsuffix(local.dns_zone, ".")}"
  # Skip public DNS records if public zone is the same as main zone (avoid duplicates)
  public_zone_is_different = var.public_dns_zone_name != "" && var.public_dns_zone_name != var.dns_zone_name
}

data "google_dns_managed_zone" "zone" {
  name    = var.dns_zone_name
  project = var.project_id
}

resource "google_compute_global_address" "global_ip" {
  project      = var.project_id
  name         = "${var.name_prefix}-global-lb-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_health_check" "logscale" {
  project = var.project_id
  name    = "${var.name_prefix}-logscale-health-check"

  check_interval_sec  = var.health_check_interval_sec
  timeout_sec         = var.health_check_timeout_sec
  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = var.health_check_type == "HTTP" ? [1] : []
    content {
      port         = var.health_check_port
      request_path = var.health_check_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.health_check_type == "HTTPS" ? [1] : []
    content {
      port         = var.health_check_port
      request_path = var.health_check_path
    }
  }

  dynamic "tcp_health_check" {
    for_each = var.health_check_type == "TCP" ? [1] : []
    content {
      port = var.health_check_port
    }
  }

  log_config {
    enable = var.enable_logging
  }
}

resource "google_compute_backend_service" "logscale" {
  project = var.project_id
  name    = "${var.name_prefix}-logscale-backend"

  protocol              = "HTTPS"
  port_name             = "https"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  health_checks = [google_compute_health_check.logscale.id]

  connection_draining_timeout_sec = var.connection_draining_timeout_sec

  dynamic "backend" {
    for_each = var.primary_neg_self_link != "" ? [1] : []
    content {
      group           = var.primary_neg_self_link
      balancing_mode  = "RATE"
      max_rate        = 10000
      capacity_scaler = var.primary_capacity_scaler
    }
  }

  dynamic "backend" {
    for_each = var.primary_neg_self_link == "" ? var.primary_instance_group : []
    content {
      group           = backend.value
      balancing_mode  = "UTILIZATION"
      max_utilization = 0.8
      capacity_scaler = var.primary_capacity_scaler
    }
  }

  dynamic "backend" {
    for_each = var.secondary_neg_self_link != "" ? [1] : []
    content {
      group           = var.secondary_neg_self_link
      balancing_mode  = "RATE"
      max_rate        = 10000
      capacity_scaler = var.secondary_capacity_scaler
    }
  }

  dynamic "backend" {
    for_each = var.secondary_neg_self_link == "" ? var.secondary_instance_group : []
    content {
      group           = backend.value
      balancing_mode  = "UTILIZATION"
      max_utilization = 0.8
      capacity_scaler = var.secondary_capacity_scaler
    }
  }

  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode = "CACHE_ALL_STATIC"
    }
  }

  log_config {
    enable      = var.enable_logging
    sample_rate = var.log_sample_rate
  }
}

resource "google_compute_url_map" "logscale" {
  project         = var.project_id
  name            = "${var.name_prefix}-logscale-url-map"
  default_service = google_compute_backend_service.logscale.id
}

resource "google_compute_managed_ssl_certificate" "logscale" {
  project = var.project_id
  name    = "${var.name_prefix}-logscale-ssl-cert"

  managed {
    domains = [local.global_fqdn]
  }

  lifecycle {
    ignore_changes = [managed[0].domains]
  }
}

resource "google_compute_target_https_proxy" "logscale" {
  project          = var.project_id
  name             = "${var.name_prefix}-logscale-https-proxy"
  url_map          = google_compute_url_map.logscale.id
  ssl_certificates = [google_compute_managed_ssl_certificate.logscale.id]

  ssl_policy = var.ssl_policy != "" ? var.ssl_policy : null
}

resource "google_compute_global_forwarding_rule" "logscale_https" {
  project               = var.project_id
  name                  = "${var.name_prefix}-logscale-https-fwd"
  target                = google_compute_target_https_proxy.logscale.id
  ip_address            = google_compute_global_address.global_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  labels = var.labels
}

resource "google_compute_url_map" "http_redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-logscale-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "http_redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-logscale-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "logscale_http" {
  project               = var.project_id
  name                  = "${var.name_prefix}-logscale-http-fwd"
  target                = google_compute_target_http_proxy.http_redirect.id
  ip_address            = google_compute_global_address.global_ip.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  labels = var.labels
}

resource "google_dns_record_set" "global" {
  project      = var.project_id
  name         = "${local.global_fqdn}."
  type         = "A"
  ttl          = var.dns_ttl
  managed_zone = var.dns_zone_name
  rrdatas      = [google_compute_global_address.global_ip.address]
}

resource "google_dns_record_set" "primary_cluster" {
  count = var.create_cluster_dns_records && var.primary_cluster_hostname != "" && var.primary_cluster_ip != "" ? 1 : 0

  project      = var.project_id
  name         = "${var.primary_cluster_hostname}.${local.dns_zone}"
  type         = "A"
  ttl          = var.dns_ttl
  managed_zone = var.dns_zone_name
  rrdatas      = [var.primary_cluster_ip]
}

resource "google_dns_record_set" "secondary_cluster" {
  count = var.create_cluster_dns_records && var.secondary_cluster_hostname != "" && var.secondary_cluster_ip != "" ? 1 : 0

  project      = var.project_id
  name         = "${var.secondary_cluster_hostname}.${local.dns_zone}"
  type         = "A"
  ttl          = var.dns_ttl
  managed_zone = var.dns_zone_name
  rrdatas      = [var.secondary_cluster_ip]
}

data "google_dns_managed_zone" "public_zone" {
  count   = var.create_public_dns_records && local.public_zone_is_different ? 1 : 0
  name    = var.public_dns_zone_name
  project = var.project_id
}

resource "google_dns_record_set" "public_primary" {
  count = var.create_public_dns_records && local.public_zone_is_different && var.primary_cluster_hostname != "" && var.primary_cluster_ip != "" ? 1 : 0

  project      = var.project_id
  name         = "${var.primary_cluster_hostname}.${data.google_dns_managed_zone.public_zone[0].dns_name}"
  type         = "A"
  ttl          = var.dns_ttl
  managed_zone = var.public_dns_zone_name
  rrdatas      = [var.primary_cluster_ip]
}

resource "google_dns_record_set" "public_secondary" {
  count = var.create_public_dns_records && local.public_zone_is_different && var.secondary_cluster_hostname != "" && var.secondary_cluster_ip != "" ? 1 : 0

  project      = var.project_id
  name         = "${var.secondary_cluster_hostname}.${data.google_dns_managed_zone.public_zone[0].dns_name}"
  type         = "A"
  ttl          = var.dns_ttl
  managed_zone = var.public_dns_zone_name
  rrdatas      = [var.secondary_cluster_ip]
}

resource "google_dns_record_set" "public_global" {
  count = var.create_public_dns_records && local.public_zone_is_different ? 1 : 0

  project      = var.project_id
  name         = "${var.global_hostname}.${data.google_dns_managed_zone.public_zone[0].dns_name}"
  type         = "A"
  ttl          = var.dns_ttl
  managed_zone = var.public_dns_zone_name
  rrdatas      = [google_compute_global_address.global_ip.address]
}
