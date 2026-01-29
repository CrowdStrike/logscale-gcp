# Terraform State Bucket and Prefix
# NOTE: This bucket name must also be updated in variables.tf (logscale_gcp_tf_state_bucket)
terraform {
  backend "gcs" {
    bucket = "XXXXX-logscale-terraform-state-v1"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}