# Terraform State Bucket and Prefix
terraform {
  backend "gcs" {
    bucket = "XXXXXX-logscale-terraform-state-v1"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}