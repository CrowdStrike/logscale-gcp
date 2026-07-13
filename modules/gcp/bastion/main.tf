locals {
  zone          = var.zone != "" ? var.zone : "${var.region}-a"
  instance_name = var.instance_name != "" ? var.instance_name : "${var.infrastructure_prefix}-bastion"
  sa_account_id = var.service_account_name != "" ? var.service_account_name : "${var.infrastructure_prefix}-bastion-sa"
}

data "google_service_account" "bastion" {
  account_id = local.sa_account_id
  project    = var.project_id
}

resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.network_name}-allow-iap-ssh"
  network = var.network_id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP TCP forwarding source range — https://cloud.google.com/iap/docs/using-tcp-forwarding
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

resource "google_compute_instance" "bastion" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = local.zone
  project      = var.project_id
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = var.image_type
    }
  }

  network_interface {
    subnetwork = var.subnetwork_id
  }

  shielded_instance_config {
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    block-project-ssh-keys = true
    enable-oslogin         = "TRUE"
  }

  metadata_startup_script = <<-STARTUP
  #!/bin/bash
  set -e
  apt-get update -y
  apt-get install -y apt-transport-https ca-certificates curl gnupg tinyproxy

  # kubectl
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

  # gcloud CLI
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.asc
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list

  apt-get update -y
  apt-get install -y kubectl google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin

  # tinyproxy: allow localhost connections for SSH tunnel
  sed -i '/^Allow /d' /etc/tinyproxy/tinyproxy.conf
  echo "Allow 127.0.0.1" >> /etc/tinyproxy/tinyproxy.conf
  echo "Allow ::1" >> /etc/tinyproxy/tinyproxy.conf
  systemctl restart tinyproxy
  STARTUP

  lifecycle {
    ignore_changes = [metadata["ssh-keys"]]
  }

  service_account {
    email  = data.google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }
}
