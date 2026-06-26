output "instance_name" {
  description = "Bastion instance name"
  value       = google_compute_instance.bastion.name
}

output "instance_zone" {
  description = "Zone of the bastion instance"
  value       = google_compute_instance.bastion.zone
}

output "ssh_command" {
  description = "SSH via IAP tunnel"
  value       = "gcloud compute ssh ${google_compute_instance.bastion.name} --project=${var.project_id} --zone=${local.zone} --tunnel-through-iap"
}

output "ssh_proxy_command" {
  description = "SSH with tinyproxy tunnel for kubectl access"
  value       = "gcloud compute ssh ${google_compute_instance.bastion.name} --project=${var.project_id} --zone=${local.zone} --tunnel-through-iap --ssh-flag=\"-4 -L8888:localhost:8888 -N -q -f\""
}

output "service_account_email" {
  description = "Bastion service account email"
  value       = data.google_service_account.bastion.email
}
