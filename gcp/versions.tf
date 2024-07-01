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

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.10.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.1.1"
    }

  }
}
