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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0"  # Match logscale-kubernetes requirement
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.2, < 3.0.0"  # Match logscale-kubernetes requirement
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.1"  # Match logscale-kubernetes requirement
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"  # Match logscale-kubernetes requirement
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.1"  # Match logscale-kubernetes requirement
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4.2"  # Match logscale-kubernetes requirement
    }
  }
}
