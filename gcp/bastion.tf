# Creates a basion host, this can be disabled by setting var.bastion_host_enabled = false when applying or by
# using the override file

resource "google_compute_instance" "bastion" {
  count = var.bastion_host_enabled ? 1 : 0 
  name         = (var.bastion_instance_name != "" ? var.bastion_instance_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bastion")
  machine_type = var.bastion_machine_type
  zone         = var.zone
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = var.bastion_image_type
    }
  }

  network_interface {
    network    = (var.gcp_network_name != "" ? var.gcp_network_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-network")
    subnetwork = (var.gcp_subnetwork_name != "" ? var.gcp_subnetwork_name : "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-subnetwork-${var.region}")
  }

  shielded_instance_config {
    enable_vtpm = true
  }

  metadata = {
    block-project-ssh-keys = true
  }

  metadata_startup_script = <<-EOF
  #!/bin/bash
  sudo apt-get update
  # Install kubectl
  sudo apt-get install -y apt-transport-https ca-certificates curl
  sudo mkdir -p /etc/apt/keyrings/
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  # Install gcloud-sdk
  sudo snap remove google-cloud-cli
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
  sudo apt-get update && sudo apt-get install -y google-cloud-cli kubectl google-cloud-cli-gke-gcloud-auth-plugin gnupg software-properties-common
  # Install terraform
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt-get install -y terraform tinyproxy
  sudo sed -i "225i Allow localhost" /etc/tinyproxy/tinyproxy.conf
  sudo systemctl restart tinyproxy.service
  EOF

  lifecycle {
    ignore_changes = [
      metadata.ssh_keys
    ]
  }

  service_account {
    email  = google_service_account.bastion_service_account[0].email
    scopes = ["cloud-platform"]
  }

  depends_on = [
    google_compute_network.network,
    google_compute_subnetwork.subnetwork,
    google_service_account.bastion_service_account
  ]
}

output "bastion_hostname" {
  value = "${var.infrastructure_prefix}-${random_string.env_identifier_rand.result}-bastion"
}

output "bastion_ssh" {
  value = "gcloud compute ssh ${google_compute_instance.bastion[0].name} --project=${var.project_id} --zone=${var.zone}  --tunnel-through-iap"
}

output "bastion_ssh_proxy" {
  value = "gcloud compute ssh ${google_compute_instance.bastion[0].name} --project=${var.project_id} --zone=${var.zone}  --tunnel-through-iap --ssh-flag=\"-4 -L8888:localhost:8888 -N -q -f\""
}