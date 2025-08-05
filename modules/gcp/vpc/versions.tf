# modules/gcp/vpc/versions.tf

terraform {
  required_version = ">= 1.1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.83.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.83.0"
    }
  }
}
