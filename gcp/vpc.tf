// Setup networking

resource "google_compute_network" "network" {
  project                 = var.project_id
  name                    = (var.gcp_network_name != "" ? var.gcp_network_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-network")
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork" {
  name                     = (var.gcp_subnetwork_name != "" ? var.gcp_subnetwork_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-subnetwork-${var.region}")
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
  count    = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  provider = google-beta

  name          = (var.gcp_subnetwork_proxy_name != "" ? var.gcp_subnetwork_proxy_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-subnetwork-proxy-${var.region}")
  project       = var.project_id
  ip_cidr_range = var.gcp_subnetwork_proxy_cidr_range
  region        = var.region
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.network.id

}
//Firewalls

resource "google_compute_firewall" "allow-ssh" {
  name    = "${google_compute_network.network.name}-allow-ssh"
  network = google_compute_network.network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # only allow IP addresses that gcloud IAP uses for TCP forwarding.

  depends_on = [
    google_compute_network.network,
  ]

  target_tags = ["bastion"]
}


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
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0

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
  project      = var.project_id
  name         = (var.gce_ingress_ip_name != "" ? var.gce_ingress_ip_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-gce-ingress-ip")
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

// NAT Config

resource "google_compute_router" "router" {
  name    = (var.gcp_network_router_name != "" ? var.gcp_network_router_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-network-router")
  region  = var.region
  network = google_compute_network.network.name

  depends_on = [
    google_compute_network.network,
  ]
}

resource "google_compute_address" "nat_egress_ip" {
  name         = (var.gcp_network_nat_ip_name != "" ? var.gcp_network_nat_ip_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-egress-ip")
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_router_nat" "nat_manual" {
  name   = (var.gcp_network_router_nat_name != "" ? var.gcp_network_router_nat_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-nat-router")
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

output "logscale-nat-ip" {
  value = google_compute_address.nat_egress_ip.address
}

output "gce-ingress-external-static-ip" {
  value = google_compute_global_address.gce_ingress_ip.address
}

output "network_id" {
  value = google_compute_network.network.id
}

output "subnetwork_id" {
  value = google_compute_subnetwork.subnetwork.id
}

output "network_name" {
  value = google_compute_network.network.name
}
