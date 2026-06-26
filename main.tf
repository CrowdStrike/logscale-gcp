# VPC Module
module "vpc" {
  source = "./modules/gcp/vpc"

  # Basic configuration
  project_id            = var.project_id
  region                = var.region
  infrastructure_prefix = var.infrastructure_prefix

  # Network configuration
  gcp_network_name                = var.gcp_network_name
  gcp_subnetwork_name             = var.gcp_subnetwork_name
  gcp_cidr_range                  = var.gcp_cidr_range
  gcp_subnetwork_proxy_name       = var.gcp_subnetwork_proxy_name
  gcp_subnetwork_proxy_cidr_range = var.gcp_subnetwork_proxy_cidr_range

  # LogScale configuration
  logscale_cluster_type = var.logscale_cluster_type

  # Static IP names
  gce_ingress_ip_name         = var.gce_ingress_ip_name
  gcp_network_nat_ip_name     = var.gcp_network_nat_ip_name
  gcp_network_router_name     = var.gcp_network_router_name
  gcp_network_router_nat_name = var.gcp_network_router_nat_name

  # External load balancer toggle
  enable_global_lb = var.enable_global_lb

  # Per-cluster ingress mode (independent of GLB)
  ingress_mode = var.ingress_mode

}

# Bastion Module (optional — IAP SSH jump host for private GKE clusters)
module "bastion" {
  count  = var.bastion_host_enabled ? 1 : 0
  source = "./modules/gcp/bastion"

  project_id            = var.project_id
  region                = var.region
  infrastructure_prefix = var.infrastructure_prefix

  network_id    = module.vpc.network_id
  subnetwork_id = module.vpc.subnetwork_id
  network_name  = module.vpc.network_name

  machine_type         = var.bastion_machine_type
  image_type           = var.bastion_image_type
  instance_name        = var.bastion_instance_name
  service_account_name = var.bastion_service_account_name
}

# Cloud Armor (external-restricted ingress only)
module "cloud_armor" {
  count  = var.ingress_mode == "external-restricted" ? 1 : 0
  source = "./modules/gcp/cloud-armor"

  project_id    = var.project_id
  name_prefix   = var.infrastructure_prefix
  allowed_cidrs = var.ingress_allowed_cidrs
}

# GKE Module
module "gke" {
  source = "./modules/gcp/gke"

  # Basic configuration
  project_id            = var.project_id
  region                = var.region
  zone                  = var.zone
  infrastructure_prefix = var.infrastructure_prefix
  name                  = var.name

  # Cluster versioning
  min_master_version = var.min_master_version
  node_pool_version  = var.node_pool_version
  auto_upgrade       = var.auto_upgrade

  # Cluster configuration
  enable_shielded_nodes    = var.enable_shielded_nodes
  logging_service          = var.logging_service
  monitoring_service       = var.monitoring_service
  remove_default_node_pool = var.remove_default_node_pool
  private_nodes            = var.private_nodes
  vpa_enabled              = var.vpa_enabled
  deletion_protection      = var.deletion_protection

  # Network configuration (from VPC module)
  network_name             = module.vpc.network_name
  subnetwork_name          = module.vpc.subnetwork_name
  cluster_ipv4_cidr_block  = var.cluster_ipv4_cidr_block
  services_ipv4_cidr_block = var.services_ipv4_cidr_block
  master_ipv4_cidr_block   = var.master_ipv4_cidr_block

  # Maintenance configuration
  maintenance_policy_start_time = var.maintenance_policy_start_time

  # Node pool configuration
  image_type            = var.image_type
  node_pool_auth_scopes = var.node_pool_auth_scopes

  # LogScale specific configuration
  logscale_gke_cluster_name                 = var.logscale_gke_cluster_name
  logscale_cluster_size                     = var.logscale_cluster_size
  logscale_cluster_type                     = var.logscale_cluster_type
  cluster_size_definitions                  = local.cluster_size_rendered
  # When bastion is enabled, include the VPC subnet CIDR in authorized networks
  # so the bastion can always reach the K8s API (covers both private and public endpoint modes).
  ip_ranges_allowed_to_kubeapi = var.bastion_host_enabled ? distinct(concat(
    var.ip_ranges_allowed_to_kubeapi,
    [var.gcp_cidr_range]
  )) : var.ip_ranges_allowed_to_kubeapi
  logscale_access_logs_bucket               = var.logscale_access_logs_bucket != "" ? var.logscale_access_logs_bucket : local.actual_access_logs_bucket_name
  gcs_bucket_name                           = var.gcs_bucket_name != "" ? var.gcs_bucket_name : local.actual_gcs_bucket_name
  logscale_cluster_k8s_service_account_name = var.logscale_cluster_k8s_service_account_name
  logscale_cluster_k8s_namespace_name       = var.logscale_cluster_k8s_namespace_name
  logscale_tf_service_account_name          = var.logscale_tf_service_account_name
  kubernetes_private_cluster_enabled        = var.kubernetes_private_cluster_enabled
  provision_kafka_servers                   = var.provision_kafka_servers

  # Storage
  gcs_force_destroy = var.gcs_force_destroy

  # DR Configuration
  dr                          = var.dr
  dr_primary_gcs_bucket       = var.dr_primary_gcs_bucket
  primary_remote_state        = var.primary_remote_state_config != null ? data.terraform_remote_state.primary[0] : null
  existing_gcs_encryption_key = var.existing_gcs_encryption_key

  # IAM Management
  manage_terraform_service_account = var.manage_terraform_service_account
  # When true, reuses a pre-existing GCP SA for workload identity (no SA creation)
  use_existing_gcp_sa  = var.use_existing_gcp_sa
  existing_gcp_sa_name = var.existing_gcp_sa_name

  # LogScale resource name prefix (for workload identity bindings)
  resource_name_prefix = var.resource_name_prefix

  depends_on = [module.vpc]
}

check "private_cluster_requires_bastion" {
  assert {
    condition     = !var.kubernetes_private_cluster_enabled || var.bastion_host_enabled
    error_message = "Private cluster (kubernetes_private_cluster_enabled=true) requires bastion_host_enabled=true. The private API endpoint is only reachable from within the VPC via the bastion's IAP tunnel."
  }
}

# Kubernetes pre-install module (namespace creation)
# Must run BEFORE logscale-prereqs which creates secrets in this namespace.
# Aligns GCP with AWS/Azure/OCI which all create the namespace in a pre-install step.
module "kubernetes_pre_install" {
  source = "./modules/kubernetes/pre-install"

  providers = {
    kubernetes = kubernetes
  }

  logscale_namespace = var.logscale_cluster_k8s_namespace_name

  depends_on = [module.gke]
}

# Kubernetes post-install module (GCP-specific services, ingresses, secrets)
# Runs AFTER namespace exists (pre-install) and logscale-prereqs.
module "kubernetes_post_install" {
  source = "./modules/kubernetes/post-install"

  # Configure the kubernetes provider
  providers = {
    kubernetes = kubernetes
    helm       = helm
    random     = random
  }


  # Cluster connection info
  cluster_endpoint       = module.gke.cluster_endpoint
  cluster_ca_certificate = module.gke.cluster_ca_certificate
  cluster_name           = module.gke.cluster_name

  # Project and region
  project_id = var.project_id
  region     = var.region

  # LogScale configuration
  logscale_cluster_type               = var.logscale_cluster_type
  logscale_cluster_k8s_namespace_name = var.logscale_cluster_k8s_namespace_name
  public_url                          = var.public_url
  logscale_cluster_name               = local.logscale_cluster_name
  humio_cluster_instance_name         = var.humio_cluster_instance_name
  logscale_gce_ingress_ip             = module.vpc.gce_ingress_ip_name

  # GCP-specific ingress configuration (decoupled from enable_global_lb)
  ingress_mode            = var.ingress_mode
  enable_gcp_ingress      = var.ingress_mode != "disabled"
  enable_gke_ingress      = var.ingress_mode == "external-restricted"
  enable_internal_ingress = var.ingress_mode == "internal"
  cloud_armor_policy_name = var.ingress_mode == "external-restricted" ? module.cloud_armor[0].security_policy_name : ""
  gcp_static_ip_name      = module.vpc.gce_ingress_ip_name
  gcp_ingress_annotations = {}
  gcp_service_annotations = {}

  # DR Configuration
  dr                                          = var.dr
  primary_remote_state                        = var.primary_remote_state_config != null ? data.terraform_remote_state.primary[0] : null
  existing_gcs_encryption_key                 = var.existing_gcs_encryption_key
  gcp_recover_from_encryption_key_secret_name = var.gcp_recover_from_encryption_key_secret_name
  gcp_recover_from_encryption_key_secret_key  = var.gcp_recover_from_encryption_key_secret_key
  resource_name_prefix                        = var.resource_name_prefix

  # GLB NodePort configuration
  # Named port is needed on BOTH primary and secondary clusters when using GLB
  logscale_ui_nodeport  = var.logscale_ui_nodeport
  enable_glb_named_port = var.enable_glb_named_port != null ? var.enable_glb_named_port : var.enable_global_lb
  instance_group_urls   = module.gke.instance_group_urls

  depends_on = [module.gke, module.kubernetes_pre_install]
}

module "logscale" {
  source = "git::https://github.com/CrowdStrike/logscale-kubernetes.git?ref=main"

  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  kubeconfig_path      = local.kubeconfig_filepath
  k8s_cluster_context  = module.gke.cluster_name
  k8s_namespace_prefix = var.logscale_cluster_k8s_namespace_name
  resource_name_prefix = var.resource_name_prefix

  dr                       = var.dr
  dr_use_dedicated_routing = var.dr_use_dedicated_routing

  topo_lvm_chart_version = var.topo_lvm_chart_version
  gateway_api_version    = var.gateway_api_version

  # GCP uses GKE-native ingress; Gateway API resources are created by the shared
  # module but not used for traffic routing. Valid parametersRef is required by
  # the GatewayClass spec validation.
  deploy_gateway_api      = false
  gateway_controller_name = "example.com/no-op"
  gateway_parameters_ref = {
    group = "networking.gke.io"
    kind  = "GCPGatewayPolicy"
    name  = "${local.logscale_cluster_name}-gateway-policy"
  }

  # kafka
  provision_kafka_servers = var.provision_kafka_servers

  # cert manager
  cm_version              = var.cm_version
  cm_repo                 = var.cm_repo
  cm_namespace            = var.cm_namespace
  cert_ca_server          = var.ca_server
  cert_issuer_name        = var.issuer_name
  cert_issuer_email       = var.issuer_email
  cert_issuer_kind        = var.issuer_kind
  cert_issuer_private_key = var.issuer_private_key

  # strimzi kafka operator
  strimzi_operator_version       = var.strimzi_operator_version
  strimzi_operator_chart_version = var.strimzi_operator_chart_version

  # logscale
  logscale_cluster_size        = var.logscale_cluster_size
  logscale_cluster_type        = var.logscale_cluster_type
  logscale_license             = var.humiocluster_license
  logscale_public_fqdn         = var.public_url
  logscale_namespace           = var.logscale_cluster_k8s_namespace_name
  logscale_image_version       = var.logscale_image_version
  humio_operator_chart_version = var.humio_operator_chart_version
  humio_operator_version       = var.humio_operator_version
  humio_operator_extra_values = merge(var.humio_operator_extra_values,
    var.dr == "standby" ? { "replicas" = "0" } : {}
  )

  # PDF render service (disabled by default)
  enable_pdf_render_service     = false
  pdf_render_service_image      = "humio/pdf-render-service:0.1.2--build-104--sha-9a7598de95bb9775b6f59d874c37a206713bae01"
  pdf_render_service_node_count = 2

  # Pass the full cluster size configuration with GCP-specific overrides
  node_group_definitions = merge(local.cluster_size_rendered[var.logscale_cluster_size], {
    # Kafka storage class for GCP
    kafka_broker_data_storage_class = "premium-rwo"
    }, var.dr == "standby" ? {
    logscale_target_replication_factor = 1
  } : {})

  # GCP-specific environment variables
  # Note: Use the same structure as AWS - only include fields that have values
  # The logscale module handles the merging correctly with its lookup() logic
  user_logscale_envvars = concat(
    # Base environment variables with simple values (all clusters)
    [
      {
        "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
        "value" = "true"
      },
      {
        "name"  = "GCP_STORAGE_BUCKET"
        "value" = module.gke.gke_storage_bucket
      },
      {
        "name"  = "ENABLE_ALERTS"
        "value" = var.dr == "standby" ? "false" : "true"
      }
    ],
    # Base environment variables with secretKeyRef (all clusters)
    [
      {
        "name" = "GCP_STORAGE_ENCRYPTION_KEY"
        "valueFrom" = {
          "secretKeyRef" = {
            "key"  = "gcp-storage-encryption-key"
            "name" = local.gcp_encryption_key_secret_name
          }
        }
      }
    ],
    # DR recovery environment variables (present whenever a recovery bucket is configured).
    # Not gated on dr=="standby" because promotion (standby→active) still needs these
    # for LogScale to do final catch-up from the primary's GCS bucket.
    local.final_gcp_recover_from_bucket != "" ? [
      {
        "name"  = "GCP_RECOVER_FROM_BUCKET"
        "value" = local.final_gcp_recover_from_bucket
      },
      {
        "name"  = "GCP_RECOVER_FROM_WORKLOAD_IDENTITY"
        "value" = "true"
      },
      {
        "name"  = "GCP_RECOVER_FROM_REPLACE_REGION"
        "value" = local.final_gcp_recover_from_replace_region
      },
      # NOTE: ALLOW_KAFKA_RESET_UNTIL_TIMESTAMP_MS is NOT required when GCP_RECOVER_FROM_BUCKET is set.
      # LogScale automatically enables allowKafkaReset when bucketStorageRecoverFrom is configured.
    ] : [],
    # GCP_RECOVER_FROM_REPLACE_BUCKET: only include when explicitly set.
    # LogScale crashes with StringIndexOutOfBoundsException if this is empty string.
    local.final_gcp_recover_from_replace_bucket != null ? [
      {
        "name"  = "GCP_RECOVER_FROM_REPLACE_BUCKET"
        "value" = local.final_gcp_recover_from_replace_bucket
      },
    ] : [],
    # DR recovery encryption key (present whenever a recovery bucket is configured)
    local.final_gcp_recover_from_bucket != "" ? [
      {
        "name" = "GCP_RECOVER_FROM_ENCRYPTION_KEY"
        "valueFrom" = {
          "secretKeyRef" = {
            "key"  = local.gcp_dr_encryption_key_secret_key
            "name" = local.gcp_dr_encryption_key_secret_name
          }
        }
      }
    ] : []
  )

  extra_humio_cluster_spec = {
    humioServiceAccountAnnotations = {
      "iam.gke.io/gcp-service-account" = module.gke.gcs_workload_identity.gcp_service_account_email
    }
    extraVolumes = [
      {
        name = "trust-store"
        secret = {
          secretName = "${module.logscale.cluster_name_prefix}-strimzi-kafka-cluster-ca-cert"
        }
      }
    ]
    extraHumioVolumeMounts = [
      {
        name      = "trust-store"
        mountPath = "/tmp/kafka"
        readOnly  = true
      }
    ]
  }

  # Configurable: GCP can use Google Managed Certificates for ingress TLS,
  # but cert-manager must still be installed when TopoLVM is enabled
  # (its webhook controller requires a cert-manager-issued TLS certificate).
  use_own_certificate_for_ingress = var.use_own_certificate_for_ingress

  # Pass Workload Identity annotations to all node pools (UI, Ingest)
  humio_service_account_annotations = {
    "iam.gke.io/gcp-service-account" = module.gke.gcs_workload_identity.gcp_service_account_email
  }

  depends_on = [module.gke, module.kubernetes_post_install]
}

# DR Cloud Function Module (for standby clusters)
module "dr_failover_function" {
  count  = var.dr_cloud_function_enabled && var.dr == "standby" ? 1 : 0
  source = "./modules/gcp/dr-failover-function"

  project_id                   = var.project_id
  region                       = var.region
  cluster_name                 = module.gke.cluster_name
  cluster_location             = module.gke.cluster_location
  logscale_namespace           = var.logscale_cluster_k8s_namespace_name
  target_node_count            = var.dr_cloud_function_target_node_count
  function_timeout             = var.dr_cloud_function_timeout
  function_memory_mb           = var.dr_cloud_function_memory_mb
  pre_failover_failure_seconds = var.dr_cloud_function_pre_failover_failure_seconds
  dr_enabled                   = var.dr_cloud_function_enabled
  primary_health_check_id      = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.primary_health_check_id, "") : ""
  secondary_health_check_id    = ""
  dns_zone_name                = data.google_dns_managed_zone.env_dns_zone[0].name
  primary_hostname             = var.primary_logscale_hostname
  secondary_hostname           = var.secondary_logscale_hostname
  global_hostname              = "${var.global_logscale_hostname}.${trimsuffix(data.google_dns_managed_zone.env_dns_zone[0].dns_name, ".")}"

  glb_backend_service_name = var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.global_lb_backend_service_name, "") : var.dr_glb_backend_service_name
  enable_glb_health_alert  = (var.primary_remote_state_config != null ? try(data.terraform_remote_state.primary[0].outputs.global_lb_backend_service_name, "") : var.dr_glb_backend_service_name) != ""
  humiocluster_name        = module.logscale.cluster_name_prefix

  dr_function_service_account_email = var.dr_function_service_account_email
  secondary_instance_group_urls     = module.gke.instance_group_urls

  # Pre-failover cleanup
  gcs_bucket_name        = var.gcs_bucket_name
  kafka_bootstrap_server = "${module.logscale.cluster_name_prefix}-strimzi-kafka-kafka-bootstrap.${var.logscale_cluster_k8s_namespace_name}.svc.cluster.local:9093"

  depends_on = [module.gke, module.kubernetes_post_install]
}

# DNS Failover Module (creates both individual A record and global CNAME failover)
# - Active cluster: creates global DNS failover + public DNS A record (when GLB NOT enabled)
# - Standby cluster: creates only public DNS A record (no global DNS management)
# - Disabled when GLB is enabled (GLB handles all DNS)
module "dns_failover" {
  count  = !var.enable_global_lb && ((var.manage_global_dns && var.dr == "active") || var.private_dns_zone_name != "" || var.public_dns_zone_name != "") ? 1 : 0
  source = "./modules/gcp/dns-failover"

  project_id         = var.project_id
  dns_zone_name      = data.google_dns_managed_zone.env_dns_zone[0].name
  global_hostname    = var.global_logscale_hostname
  primary_hostname   = var.primary_logscale_hostname
  secondary_hostname = var.secondary_logscale_hostname
  cluster_hostname   = var.dr == "active" ? var.primary_logscale_hostname : var.secondary_logscale_hostname
  cluster_ip_address = module.vpc.gce_ingress_ip_address
  manage_global_dns  = var.manage_global_dns && var.dr == "active"
  ttl                = 30
  health_check_path  = "/api/v1/status"
  health_check_port  = 443

  private_dns_zone_name = var.private_dns_zone_name

  public_dns_zone_name = var.public_dns_zone_name
  public_dns_hostname  = var.dr == "active" ? var.primary_logscale_hostname : var.secondary_logscale_hostname

  depends_on = [module.vpc]
}

# Global Load Balancer Module (primary only, provides health-based DR failover)
# This replaces WRR DNS routing with native GCP health-check-based failover
# Also handles all DNS record creation (global + per-cluster)
# Secondary backend is automatically discovered via remote state when secondary cluster exists
module "global_lb" {
  count  = var.enable_global_lb && var.dr == "active" ? 1 : 0
  source = "./modules/gcp/global-lb"

  project_id      = var.project_id
  name_prefix     = var.global_logscale_hostname
  global_hostname = var.global_logscale_hostname
  dns_zone_name   = data.google_dns_managed_zone.env_dns_zone[0].name

  primary_neg_self_link  = var.global_lb_primary_neg_self_link
  primary_instance_group = var.global_lb_primary_neg_self_link == "" ? module.gke.instance_group_urls : []
  primary_region         = var.region

  # Secondary backend: prefer explicit variable, fallback to remote state lookup
  # Empty list if secondary not yet deployed (GLB works with primary only)
  secondary_neg_self_link = var.global_lb_secondary_neg_self_link
  secondary_instance_group = (
    var.global_lb_secondary_neg_self_link == "" ? try(data.terraform_remote_state.secondary[0].outputs.instance_group_urls, []) : []
  )
  secondary_region = try(data.terraform_remote_state.secondary[0].outputs.cluster_location, "")

  health_check_path = var.global_lb_health_check_path
  health_check_port = var.global_lb_health_check_port
  health_check_type = var.global_lb_health_check_type

  primary_capacity_scaler   = var.global_lb_primary_capacity
  secondary_capacity_scaler = var.global_lb_secondary_capacity

  create_cluster_dns_records = var.global_lb_create_cluster_dns
  primary_cluster_hostname   = var.primary_logscale_hostname
  secondary_cluster_hostname = var.secondary_logscale_hostname
  primary_cluster_ip         = module.vpc.gce_ingress_ip_address
  # Secondary IP: prefer explicit variable, fallback to remote state lookup
  secondary_cluster_ip = (
    var.global_lb_secondary_cluster_ip != "" ? var.global_lb_secondary_cluster_ip :
    try(data.terraform_remote_state.secondary[0].outputs.gce_ingress_ip_address, "")
  )

  create_public_dns_records = var.public_dns_zone_name != ""
  public_dns_zone_name      = var.public_dns_zone_name

  labels = var.common_labels

  depends_on = [module.gke]
}

# Workload Identity IAM binding for LogScale node pool ServiceAccounts
# This binding uses the prefixed SA names generated by module.logscale (e.g., z7su31-dr-primary-humio)
# Must be at root level to avoid circular dependency - module.gke depends on module.logscale for the prefix
resource "google_service_account_iam_member" "logscale_nodepool_wl_binding" {
  for_each = toset([
    "${module.logscale.cluster_name_prefix}-humio",
    "${module.logscale.cluster_name_prefix}-ui-humio",
    "${module.logscale.cluster_name_prefix}-ingest-only-humio"
  ])

  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gke.gcs_workload_identity.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${each.value}]"

  depends_on = [module.logscale, module.gke]
}


