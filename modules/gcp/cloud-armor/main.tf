resource "google_compute_security_policy" "ingress_allowlist" {
  project     = var.project_id
  name        = "${var.name_prefix}-ingress-allowlist"
  description = "Cloud Armor IP allowlist for LogScale ingress"

  rule {
    action   = "deny(403)"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny all"
  }

  rule {
    action   = "allow"
    priority = "900"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        # Google Cloud health check probe source ranges
        # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
        src_ip_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
      }
    }
    description = "Allow GCP health check ranges"
  }

  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.allowed_cidrs
      }
    }
    description = "Allow specified CIDRs"
  }
}
