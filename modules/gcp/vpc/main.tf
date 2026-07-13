// Setup networking

resource "google_compute_network" "network" {
  project                 = var.project_id
  name                    = (var.gcp_network_name != "" ? var.gcp_network_name : "${var.infrastructure_prefix}-network")
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork" {
  name                     = (var.gcp_subnetwork_name != "" ? var.gcp_subnetwork_name : "${var.infrastructure_prefix}-subnetwork-${var.region}")
  project                  = var.project_id
  ip_cidr_range            = var.gcp_cidr_range
  region                   = var.region
  network                  = google_compute_network.network.name
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_15_MIN"
    flow_sampling        = 0.1
    metadata             = "INCLUDE_ALL_METADATA"
  }

  depends_on = [
    google_compute_network.network,
  ]
}

# Created for internal ingest LB
resource "google_compute_subnetwork" "subnetwork_proxy" {
  count    = contains(["advanced"], var.logscale_cluster_type) || var.ingress_mode == "internal" ? 1 : 0
  provider = google-beta

  name          = (var.gcp_subnetwork_proxy_name != "" ? var.gcp_subnetwork_proxy_name : "${var.infrastructure_prefix}-subnetwork-proxy-${var.region}")
  project       = var.project_id
  ip_cidr_range = var.gcp_subnetwork_proxy_cidr_range
  region        = var.region
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.network.id

}
//Firewalls

resource "google_compute_firewall" "allow-internal" {
  name    = "${google_compute_network.network.name}-allow-internal"
  network = google_compute_network.network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["80-65535"]
  }

  source_ranges = [
    var.gcp_cidr_range
  ]

  depends_on = [
    google_compute_network.network,
  ]

}

# Created for internal ingest LB
resource "google_compute_firewall" "allow_internal_subnetwork_proxy" {
  count = contains(["advanced"], var.logscale_cluster_type) || var.ingress_mode == "internal" ? 1 : 0

  name    = "${google_compute_network.network.name}-allow-subnet-proxy"
  network = google_compute_network.network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = [
    var.gcp_subnetwork_proxy_cidr_range
  ]

  depends_on = [
    google_compute_subnetwork.subnetwork_proxy,
  ]

}

//Reserved external IP for gce-ingress
resource "google_compute_global_address" "gce_ingress_ip" {
  count        = var.enable_global_lb || var.ingress_mode == "external-restricted" ? 1 : 0
  project      = var.project_id
  name         = (var.gce_ingress_ip_name != "" ? var.gce_ingress_ip_name : "${var.infrastructure_prefix}-gce-ingress-ip")
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_firewall" "allow_glb_health_check" {
  count   = var.enable_global_lb || var.ingress_mode == "external-restricted" ? 1 : 0
  name    = "${google_compute_network.network.name}-allow-glb-healthcheck"
  project = var.project_id
  network = google_compute_network.network.name

  allow {
    protocol = "tcp"
    ports    = ["31036", "10256", "8080"]
  }

  # Google Cloud health check probe source ranges
  # https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  depends_on = [
    google_compute_network.network,
  ]
}

// NAT Config

resource "google_compute_router" "router" {
  name    = (var.gcp_network_router_name != "" ? var.gcp_network_router_name : "${var.infrastructure_prefix}-network-router")
  region  = var.region
  network = google_compute_network.network.name

  depends_on = [
    google_compute_network.network,
  ]
}

resource "google_compute_address" "nat_egress_ip" {
  name         = (var.gcp_network_nat_ip_name != "" ? var.gcp_network_nat_ip_name : "${var.infrastructure_prefix}-egress-ip")
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_router_nat" "nat_manual" {
  name   = (var.gcp_network_router_nat_name != "" ? var.gcp_network_router_nat_name : "${var.infrastructure_prefix}-nat-router")
  router = google_compute_router.router.name
  region = google_compute_router.router.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = google_compute_address.nat_egress_ip.*.self_link

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  min_ports_per_vm                 = 64
  tcp_established_idle_timeout_sec = 1200
  icmp_idle_timeout_sec            = 30
  tcp_transitory_idle_timeout_sec  = 30
  udp_idle_timeout_sec             = 30

  log_config {
    filter = "ERRORS_ONLY"
    enable = true
  }
}
