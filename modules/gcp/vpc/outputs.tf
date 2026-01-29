output "logscale-nat-ip" {
  description = "NAT egress IP address"
  value       = google_compute_address.nat_egress_ip.address
}

output "gce-ingress-external-static-ip" {
  description = "GCE ingress external static IP address"
  value       = google_compute_global_address.gce_ingress_ip.address
}

output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.network.id
}

output "subnetwork_id" {
  description = "ID of the subnetwork"
  value       = google_compute_subnetwork.subnetwork.id
}

output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.network.name
}

output "subnetwork_name" {
  description = "Name of the subnetwork"
  value       = google_compute_subnetwork.subnetwork.name
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.network.self_link
}

output "subnetwork_self_link" {
  description = "Self link of the subnetwork"
  value       = google_compute_subnetwork.subnetwork.self_link
}

# Conditional outputs for advanced
output "proxy_subnetwork_id" {
  description = "ID of the proxy subnetwork (if created)"
  value       = length(google_compute_subnetwork.subnetwork_proxy) > 0 ? google_compute_subnetwork.subnetwork_proxy[0].id : null
}

output "proxy_subnetwork_name" {
  description = "Name of the proxy subnetwork (if created)"
  value       = length(google_compute_subnetwork.subnetwork_proxy) > 0 ? google_compute_subnetwork.subnetwork_proxy[0].name : null
}

output "gce_ingress_ip_name" {
  description = "Name of the GCE ingress IP address"
  value       = google_compute_global_address.gce_ingress_ip.name
}

output "gce_ingress_ip_address" {
  description = "The GCE ingress IP address"
  value       = google_compute_global_address.gce_ingress_ip.address
}
