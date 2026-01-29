# Local variables for cluster size
locals {
  cluster_size_template = jsondecode(templatefile("${path.module}/cluster_size.tpl", {}))
  cluster_size_rendered = {
    for key in keys(local.cluster_size_template) :
    key => local.cluster_size_template[key]
  }
  logscale_cluster_name = (var.logscale_gke_cluster_name != "" ? var.logscale_gke_cluster_name : "${var.infrastructure_prefix}")
  kubeconfig_filepath   = var.kubeconfig_filepath != "" ? var.kubeconfig_filepath : "~/.kube/config"
}

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

  # Cluster configuration
  enable_shielded_nodes    = var.enable_shielded_nodes
  logging_service          = var.logging_service
  monitoring_service       = var.monitoring_service
  remove_default_node_pool = var.remove_default_node_pool
  private_nodes            = var.private_nodes
  vpa_enabled              = var.vpa_enabled

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
  logscale_gke_cluster_name    = var.logscale_gke_cluster_name
  logscale_cluster_size        = var.logscale_cluster_size
  logscale_cluster_type        = var.logscale_cluster_type
  cluster_size_definitions     = local.cluster_size_rendered
  ip_ranges_allowed_to_kubeapi = var.ip_ranges_allowed_to_kubeapi
  logscale_access_logs_bucket  = var.logscale_access_logs_bucket
  gcs_bucket_name              = var.gcs_bucket_name
  logscale_cluster_k8s_service_account_name = var.logscale_cluster_k8s_service_account_name
  logscale_cluster_k8s_namespace_name = var.logscale_cluster_k8s_namespace_name
  logscale_tf_service_account_name = var.logscale_tf_service_account_name
  kubernetes_private_cluster_enabled = var.kubernetes_private_cluster_enabled
  provision_kafka_servers = var.provision_kafka_servers
  
  depends_on = [module.vpc]
}

# Check if namespace already exists
data "kubernetes_namespace" "existing_namespace" {
  metadata {
    name = var.logscale_cluster_k8s_namespace_name
  }
}

# # Kubernetes pre-install module
module "kubernetes_pre_install" {
  source = "./modules/kubernetes/pre-install"

  # Configure the kubernetes provider    
  providers = {
    kubernetes = kubernetes
    helm = helm
    random = random
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
  logscale_cluster_name         = local.logscale_cluster_name
  humio_cluster_instance_name   = var.humio_cluster_instance_name
  logscale_gce_ingress_ip       = module.vpc.gce_ingress_ip_name
  create_namespace          = true
  
  # GCP-specific ingress configuration
  enable_gcp_ingress        = true
  gcp_static_ip_name        = module.vpc.gce_ingress_ip_name
  gcp_ingress_annotations   = {}
  gcp_service_annotations   = {}

  depends_on = [module.gke, module.vpc]
}

module "logscale" {
  source = "../logscale-kubernetes"

  providers = {
    kubernetes = kubernetes
    google     = google
    helm       = helm
  }

  k8s_config_path                    = local.kubeconfig_filepath
  k8s_cluster_context                = module.gke.cluster_name
  k8s_namespace_prefix               = var.logscale_cluster_k8s_namespace_name

  # Use default resource_name_prefix = "ls" from logscale-kubernetes module

  topo_lvm_chart_version             = "15.5.2"
  nginx_ingress_helm_chart_version   = "4.12.1"

  # kafka - GCP uses Strimzi
  # byo_kafka_connection_string        = ""
  provision_kafka_servers            = true

  # GCP doesn't use nginx ingress - uses native load balancer
  deploy_nginx_ingress               = false

  # cert manager
  cm_version                         = var.cm_version
  cm_repo                            = var.cm_repo
  cm_namespace                       = var.cm_namespace
  cert_ca_server                     = var.ca_server
  cert_issuer_name                   = var.issuer_name
  cert_issuer_email                  = var.issuer_email
  cert_issuer_kind                   = var.issuer_kind
  cert_issuer_private_key            = var.issuer_private_key

  # logscale
  logscale_cluster_size              = var.logscale_cluster_size
  logscale_cluster_type              = var.logscale_cluster_type
  logscale_license                   = var.humiocluster_license
  logscale_public_fqdn               = var.public_url
  logscale_namespace                 = var.logscale_cluster_k8s_namespace_name
  logscale_image_version             = var.logscale_image_version
  humio_operator_chart_version       = var.humio_operator_chart_version
  humio_operator_version             = var.humio_operator_version
  humio_operator_extra_values        = var.humio_operator_extra_values
  
  # PDF render service (disabled by default)
  enable_pdf_render_service          = false
  pdf_render_service_image           = "humio/pdf-render-service:0.1.2--build-104--sha-9a7598de95bb9775b6f59d874c37a206713bae01"
  pdf_render_service_node_count      = 2

  # Pass the full cluster size configuration with GCP-specific overrides
  node_group_definitions = merge(local.cluster_size_rendered[var.logscale_cluster_size], {
    # Kafka storage class for GCP
    kafka_broker_data_storage_class = "premium-rwo"
  })

  # GCP-specific environment variables 
  user_logscale_envvars = [
    {
      "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
      "value" = "true"
    },
    {
      "name"  = "GCP_STORAGE_BUCKET"  
      "value" = module.gke.gke_storage_bucket
    },
    {
      "name" = "GCP_STORAGE_ENCRYPTION_KEY"
      "valueFrom" = {
        "secretKeyRef" = {
          "key"  = "gcp-storage-encryption-key"
          "name" = module.kubernetes_pre_install.gcp_storage_encryption_key_k8s_secret_name
        }
      }
    },
  ]

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

  # GCP uses Google Managed Certificates, not cert-manager
  use_own_certificate_for_ingress    = true

  # No extra nginx annotations for GCP (uses native load balancer)
  extra_nginx_annotations = {}

 depends_on = [module.kubernetes_pre_install]

}

# Additional IAM binding for LogScale service accounts created by Humio Operator
resource "google_service_account_iam_member" "logscale_workload_identity_binding" {
  for_each = toset([
    "${module.logscale.cluster_name_prefix}-humio",
    "${module.logscale.cluster_name_prefix}-ui-humio", 
    "${module.logscale.cluster_name_prefix}-ingest-only-humio"
  ])
  
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gke.gcs_workload_identity.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.logscale_cluster_k8s_namespace_name}/${each.key}]"
  
  depends_on = [module.logscale]
}


