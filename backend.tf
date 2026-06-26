# Terraform Backend Configuration for GCP
# This configuration uses Google Cloud Storage (GCS) to store Terraform state
# and provides state locking functionality

terraform {
  backend "gcs" {
    bucket = "XXXXX-logscale-terraform-state-v1"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}