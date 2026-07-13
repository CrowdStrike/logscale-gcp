
terraform {
  required_version = ">= 1.3"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.2, < 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.1"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}
