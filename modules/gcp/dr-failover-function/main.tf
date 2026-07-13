# APIs are project-level: disabling on destroy would break other workers in the same project.
resource "google_project_service" "cloudfunctions" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  count              = var.dr_enabled ? 1 : 0
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service_identity" "monitoring_sa" {
  count    = var.dr_enabled ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "monitoring.googleapis.com"

  depends_on = [google_project_service.monitoring]
}

resource "google_project_iam_member" "cloudbuild_logging" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_artifactregistry" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_storage" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_default_logging" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_default_artifactregistry" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_default_storage" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_default_cloudbuild" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

# Pub/Sub service agent identity - required for authenticated push subscriptions
resource "google_project_service_identity" "pubsub_sa" {
  count    = var.dr_enabled ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"

  depends_on = [google_project_service.pubsub]
}

# Allow Pub/Sub service agent to create OIDC tokens for authenticated push to Cloud Run
# This is required for Eventarc Pub/Sub triggers to invoke Cloud Run with authentication
resource "google_service_account_iam_member" "pubsub_token_creator" {
  count              = local.create_dr_resources ? 1 : 0
  service_account_id = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.pubsub_sa[0].email}"

  depends_on = [google_project_service_identity.pubsub_sa]
}

locals {
  # Only create DR resources for standby clusters
  create_dr_resources = var.dr_enabled && var.cluster_name != ""
  create_sa           = local.create_dr_resources && var.dr_function_service_account_email == ""
  dr_function_sa_email = (
    var.dr_function_service_account_email != ""
    ? var.dr_function_service_account_email
    : try(google_service_account.dr_function_sa[0].email, "")
  )

  # Function source code
  dr_function_source = {
    "main.py" = templatefile("${path.module}/function_source/main.py", {
      project_id        = var.project_id
      cluster_name      = var.cluster_name
      cluster_location  = var.cluster_location
      namespace         = var.logscale_namespace
      target_node_count = var.target_node_count
    })
    "requirements.txt" = file("${path.module}/function_source/requirements.txt")
  }
}

# Archive the Cloud Function source code
data "archive_file" "dr_function_source" {
  count       = local.create_dr_resources ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/dr-failover-function.zip"

  dynamic "source" {
    for_each = local.dr_function_source
    content {
      content  = source.value
      filename = source.key
    }
  }
}

# GCS bucket for Cloud Function source
resource "google_storage_bucket" "dr_function_source" {
  count    = local.create_dr_resources ? 1 : 0
  name     = "${var.project_id}-logscale-dr-function-source"
  location = var.region

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "cloudbuild_source_reader" {
  count  = local.create_dr_resources ? 1 : 0
  bucket = google_storage_bucket.dr_function_source[0].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

# Upload function source to GCS
resource "google_storage_bucket_object" "dr_function_source" {
  count  = local.create_dr_resources ? 1 : 0
  name   = "dr-failover-function-${data.archive_file.dr_function_source[0].output_md5}.zip"
  bucket = google_storage_bucket.dr_function_source[0].name
  source = data.archive_file.dr_function_source[0].output_path

  depends_on = [data.archive_file.dr_function_source]
}

# Service account for the Cloud Function (skip if pre-existing SA provided)
resource "google_service_account" "dr_function_sa" {
  count        = local.create_sa ? 1 : 0
  account_id   = "${var.cluster_name}-dr-func"
  display_name = "LogScale DR Failover Function Service Account"
  description  = "Service account for LogScale DR failover automation"
}

# IAM roles for the service account
resource "google_project_iam_member" "dr_function_gke_developer" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${local.dr_function_sa_email}"
}

resource "google_project_iam_member" "dr_function_monitoring_viewer" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${local.dr_function_sa_email}"
}

resource "google_project_iam_member" "dr_function_dns_reader" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/dns.reader"
  member  = "serviceAccount:${local.dr_function_sa_email}"
}

resource "google_project_iam_member" "dr_function_compute_lb_admin" {
  count   = local.create_dr_resources ? 1 : 0
  project = var.project_id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${local.dr_function_sa_email}"
}

# Cloud Function for DR failover automation
resource "google_cloudfunctions2_function" "dr_failover_function" {
  count    = local.create_dr_resources ? 1 : 0
  name     = "${var.cluster_name}-dr-failover"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "failover_handler"
    source {
      storage_source {
        bucket = google_storage_bucket.dr_function_source[0].name
        object = google_storage_bucket_object.dr_function_source[0].name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "${var.function_memory_mb}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = local.dr_function_sa_email

    environment_variables = {
      PROJECT_ID                     = var.project_id
      CLUSTER_NAME                   = var.cluster_name
      CLUSTER_LOCATION               = var.cluster_location
      NAMESPACE                      = var.logscale_namespace
      TARGET_NODE_COUNT              = tostring(var.target_node_count)
      HUMIOCLUSTER_NAME              = var.humiocluster_name
      PRIMARY_UPTIME_CHECK_ID        = local.create_dr_resources ? google_monitoring_uptime_check_config.primary_uptime_check[0].uptime_check_id : ""
      SKIP_PRIMARY_HEALTH_VALIDATION = tostring(var.skip_primary_health_validation)

      # Retry configuration
      MAX_RETRIES        = tostring(var.max_retries)
      BASE_DELAY_SECONDS = tostring(var.base_delay_seconds)
      MAX_DELAY_SECONDS  = tostring(var.max_delay_seconds)

      # GLB backend management (Cloud Function registers secondary during failover)
      GLB_BACKEND_SERVICE_NAME  = var.glb_backend_service_name
      GLB_PROJECT_ID            = var.project_id
      SECONDARY_INSTANCE_GROUPS = jsonencode(var.secondary_instance_group_urls)

      # Pre-failover validation configuration
      PRE_FAILOVER_FAILURE_SECONDS = tostring(var.pre_failover_failure_seconds)
      FAILOVER_COOLDOWN_SECONDS    = tostring(var.failover_cooldown_seconds)

      # Pre-failover cleanup (prevents Kafka epoch mismatch crash on boot)
      GCS_BUCKET_NAME        = var.gcs_bucket_name
      KAFKA_BOOTSTRAP_SERVER = var.kafka_bootstrap_server
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.dr_alerts[0].id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.dr_function_source[0]
    ]
  }

  depends_on = [
    google_storage_bucket_object.dr_function_source,
    google_storage_bucket_iam_member.cloudbuild_source_reader,
    google_project_iam_member.cloudbuild_logging,
    google_project_iam_member.cloudbuild_artifactregistry,
    google_project_iam_member.cloudbuild_storage,
    google_project_iam_member.compute_default_logging,
    google_project_iam_member.compute_default_artifactregistry,
    google_project_iam_member.compute_default_storage,
    google_project_iam_member.compute_default_cloudbuild,
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.run,
    google_project_service.eventarc,
    google_project_service.artifactregistry
  ]
}

# Pub/Sub topic for DR alerts
resource "google_pubsub_topic" "dr_alerts" {
  count = local.create_dr_resources ? 1 : 0
  name  = "${var.cluster_name}-dr-alerts"
}

# Health check for primary cluster monitoring
resource "google_compute_health_check" "primary_health_check" {
  count = local.create_dr_resources && var.primary_health_check_id == "" ? 1 : 0
  name  = "${var.primary_hostname}-logscale-health-check"

  timeout_sec         = 10
  check_interval_sec  = 30
  healthy_threshold   = 1
  unhealthy_threshold = 3

  https_health_check {
    port         = 443
    request_path = "/api/v1/status"
    host         = local.primary_fqdn
  }
}

# Health check for secondary cluster 
resource "google_compute_health_check" "secondary_health_check" {
  count = local.create_dr_resources ? 1 : 0
  name  = "${var.secondary_hostname}-logscale-health-check"

  timeout_sec         = 10
  check_interval_sec  = 30
  healthy_threshold   = 1
  unhealthy_threshold = 3

  https_health_check {
    port         = 443
    request_path = "/api/v1/status"
    # Use secondary-specific hostname for health check
    host = local.secondary_fqdn
  }
}

# Uptime check for primary LogScale cluster
resource "google_monitoring_uptime_check_config" "primary_uptime_check" {
  count        = local.create_dr_resources ? 1 : 0
  display_name = "${var.primary_hostname}-logscale-uptime-check"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/api/v1/status"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = local.primary_fqdn
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Alerting policy for uptime check failures
resource "google_monitoring_alert_policy" "dr_failover_alert" {
  count        = local.create_dr_resources ? 1 : 0
  display_name = "${var.cluster_name} DR Failover Alert"
  combiner     = "OR"

  conditions {
    display_name = "Primary cluster uptime check failure"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.primary_uptime_check[0].uptime_check_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.project_id"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.dr_pubsub[0].id]

  alert_strategy {
    auto_close = "86400s" # 24 hours
  }

  depends_on = [google_monitoring_uptime_check_config.primary_uptime_check]
}

# Alerting policy for GLB backend health-based failover
resource "google_monitoring_alert_policy" "glb_health_failover_alert" {
  count        = local.create_dr_resources && var.enable_glb_health_alert && var.glb_backend_service_name != "" ? 1 : 0
  display_name = "${var.cluster_name} GLB Health DR Failover Alert"
  combiner     = "OR"

  conditions {
    display_name = "Primary backend unhealthy in GLB"

    condition_threshold {
      filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/backend_request_count\" AND resource.labels.backend_target_name=\"${var.glb_backend_service_name}\" AND metric.labels.response_code_class=\"500\""

      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.backend_target_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "Primary backend serving zero requests"

    condition_threshold {
      filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/backend_request_count\" AND resource.labels.backend_target_name=\"${var.glb_backend_service_name}\" AND metric.labels.response_code_class=\"200\""

      duration        = "60s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.backend_target_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.dr_pubsub[0].id]

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = "GLB backend health alert triggered. Primary backend may be unhealthy or unreachable. DR failover function will scale up standby cluster."
    mime_type = "text/markdown"
  }
}

# Notification channel to trigger Pub/Sub
resource "google_monitoring_notification_channel" "dr_pubsub" {
  count        = local.create_dr_resources ? 1 : 0
  display_name = "LogScale DR Pub/Sub Notification"
  type         = "pubsub"

  labels = {
    topic = google_pubsub_topic.dr_alerts[0].id
  }
}

# IAM binding for alerting to publish to Pub/Sub
resource "google_pubsub_topic_iam_binding" "dr_alerts_publisher" {
  count = local.create_dr_resources ? 1 : 0
  topic = google_pubsub_topic.dr_alerts[0].name
  role  = "roles/pubsub.publisher"

  members = [
    "serviceAccount:${google_project_service_identity.monitoring_sa[0].email}",
  ]

  depends_on = [google_project_service_identity.monitoring_sa]
}

# IAM binding to allow default compute SA to invoke Cloud Run service (for Eventarc Pub/Sub trigger)
resource "google_cloud_run_service_iam_member" "dr_function_invoker" {
  count    = local.create_dr_resources ? 1 : 0
  location = var.region
  service  = "${var.cluster_name}-dr-failover"
  role     = "roles/run.invoker"
  member   = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  lifecycle {
    replace_triggered_by = [
      google_cloudfunctions2_function.dr_failover_function[0]
    ]
  }
}

data "google_project" "current" {}

data "google_dns_managed_zone" "dns_zone" {
  count = var.dns_zone_name != "" ? 1 : 0
  name  = var.dns_zone_name
}

locals {
  primary_fqdn = (
    var.primary_hostname != "" && length(data.google_dns_managed_zone.dns_zone) > 0
    ? "${var.primary_hostname}.${trimsuffix(data.google_dns_managed_zone.dns_zone[0].dns_name, ".")}"
    : var.global_hostname
  )

  secondary_fqdn = (
    var.secondary_hostname != "" && length(data.google_dns_managed_zone.dns_zone) > 0
    ? "${var.secondary_hostname}.${trimsuffix(data.google_dns_managed_zone.dns_zone[0].dns_name, ".")}"
    : var.global_hostname
  )
}
