# Terraform State Bucket and Prefix
terraform {
  backend "gcs" {
    bucket = "test-new-logscale-terraform-state-v1"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}