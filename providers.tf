# Terraform providers
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
}

# Kubernetes provider configuration
data "google_client_config" "default" {}

# Two auth modes controlled by use_kubeconfig_auth:
#   true  = kubeconfig file on disk (local dev, automated deployments with pre-generated kubeconfig)
#   false = in-line credentials from GKE module (fresh deploys, no file dependency)
locals {
  kube_config_path = var.use_kubeconfig_auth && fileexists(pathexpand(local.kubeconfig_filepath)) ? local.kubeconfig_filepath : null
  kube_host        = var.use_kubeconfig_auth ? null : "https://${module.gke.cluster_endpoint}"
  kube_token       = var.use_kubeconfig_auth ? null : data.google_client_config.default.access_token
  kube_ca_cert     = var.use_kubeconfig_auth ? null : base64decode(module.gke.cluster_ca_certificate)
}

provider "kubernetes" {
  config_path            = local.kube_config_path
  host                   = local.kube_host
  token                  = local.kube_token
  cluster_ca_certificate = local.kube_ca_cert
}

provider "helm" {
  kubernetes {
    config_path            = local.kube_config_path
    host                   = local.kube_host
    token                  = local.kube_token
    cluster_ca_certificate = local.kube_ca_cert
  }
}

provider "http" {}

provider "random" {}

provider "kubectl" {
  config_path            = local.kube_config_path
  host                   = local.kube_host
  token                  = local.kube_token
  cluster_ca_certificate = local.kube_ca_cert
  load_config_file       = false
}

