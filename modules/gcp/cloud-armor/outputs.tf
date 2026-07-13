output "security_policy_name" {
  description = "Cloud Armor security policy name for BackendConfig reference"
  value       = google_compute_security_policy.ingress_allowlist.name
}
