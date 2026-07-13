output "dr_function_name" {
  description = "Name of the DR failover Cloud Function"
  value       = local.create_dr_resources ? google_cloudfunctions2_function.dr_failover_function[0].name : null
}

output "dr_function_url" {
  description = "URL of the DR failover Cloud Function"
  value       = local.create_dr_resources ? google_cloudfunctions2_function.dr_failover_function[0].service_config[0].uri : null
}

output "dr_pubsub_topic" {
  description = "Pub/Sub topic for DR alerts"
  value       = local.create_dr_resources ? google_pubsub_topic.dr_alerts[0].name : null
}

output "primary_health_check_id" {
  description = "Primary cluster health check ID"
  value       = local.create_dr_resources && length(google_compute_health_check.primary_health_check) > 0 ? google_compute_health_check.primary_health_check[0].id : var.primary_health_check_id
}

output "secondary_health_check_id" {
  description = "Secondary cluster health check ID"
  value       = local.create_dr_resources ? google_compute_health_check.secondary_health_check[0].id : null
}

output "dr_function_service_account_email" {
  description = "Service account email for the DR function"
  value       = local.create_dr_resources ? local.dr_function_sa_email : null
}