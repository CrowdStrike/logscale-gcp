# GCP LogScale Terraform Variables -- Complete Inventory (DR Branch)

This is the complete variable inventory from the `logscale-gcp` DR branch. All variables are defined in the Terraform root module and consumed by child modules. Variables are organized by functional category.

Total variable count: ~90 variables.

---

## Basic Configuration

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `project_id` | string | -- | YES | GCP project ID |
| `region` | string | `"us-central1"` | no | GCP region |
| `zone` | string | `"us-central1-a"` | no | GCP zone |
| `infrastructure_prefix` | string | `"logscale"` | no | Prefix for all resources |
| `resource_name_prefix` | string | `"logscale"` | no | Prefix for K8s resources (max 8 chars) |
| `common_labels` | map(string) | `{}` | no | Labels applied to all resources |
| `tags` | map(string) | `{}` | no | Tags mapped to GCP labels |
| `deletion_protection` | bool | `true` | no | Prevent accidental deletion of GKE cluster |
| `gcs_force_destroy` | bool | `false` | no | Allow GCS bucket deletion even with objects present |

---

## LogScale Versions

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `humio_operator_chart_version` | string | -- | YES | Humio operator Helm chart version |
| `humio_operator_version` | string | -- | YES | Humio operator container image version |
| `logscale_image_version` | string | -- | YES | LogScale container image version |
| `strimzi_operator_version` | string | -- | YES | Strimzi operator version |
| `strimzi_operator_chart_version` | string | -- | YES | Strimzi operator Helm chart version |
| `topo_lvm_chart_version` | string | `"15.5.2"` | no | TopoLVM Helm chart version |
| `nginx_ingress_helm_chart_version` | string | `"4.12.1"` | no | NGINX Ingress controller chart version |
| `humiocluster_license` | string | `""` | no | LogScale license key |
| `humio_operator_extra_values` | map(string) | `{}` | no | Extra Helm values passed to operator chart |

---

## Certificate Manager

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `cm_namespace` | string | -- | YES | cert-manager namespace |
| `cm_repo` | string | -- | YES | cert-manager Helm repository URL |
| `cm_version` | string | -- | YES | cert-manager version |
| `issuer_kind` | string | -- | YES | Certificate issuer kind (ClusterIssuer or Issuer) |
| `issuer_name` | string | -- | YES | Certificate issuer name |
| `issuer_email` | string | -- | YES | Email for ACME registration |
| `issuer_private_key` | string | -- | YES | Issuer private key secret name |
| `ca_server` | string | -- | YES | CA server URL (e.g., Let's Encrypt staging or prod) |
| `use_own_certificate_for_ingress` | bool | `true` | no | Use cert-manager managed certificates for ingress TLS |

---

## GKE Cluster

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | `"logscale"` | no | Base cluster name |
| `logscale_gke_cluster_name` | string | `""` | no | Override for GKE cluster name (empty = use `name`) |
| `min_master_version` | string | `"1.33.5-gke.1791000"` | no | GKE control plane version |
| `node_pool_version` | string | `"1.33.5-gke.1791000"` | no | GKE node pool version |
| `image_type` | string | `"COS_CONTAINERD"` | no | Node image type |
| `enable_shielded_nodes` | bool | `true` | no | Enable shielded GKE nodes |
| `private_nodes` | string | `"true"` | no | Use private IP addresses for nodes |
| `remove_default_node_pool` | string | `"true"` | no | Remove the GKE default node pool |
| `max_pods_per_node` | string | `"20"` | no | Maximum pods per node |
| `vpa_enabled` | bool | `false` | no | Enable Vertical Pod Autoscaling |
| `cloudrun_disabled` | bool | `true` | no | Disable CloudRun addon |
| `dns_cache_config_enabled` | bool | `false` | no | Enable NodeLocal DNSCache |
| `issue_client_certificate` | bool | `false` | no | Issue client certificate for cluster auth |
| `public_url` | string | -- | YES | Public URL for LogScale UI and API |

---

## Network

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `cluster_ipv4_cidr_block` | string | `"10.0.0.0/14"` | no | Pod IP CIDR range |
| `services_ipv4_cidr_block` | string | `"172.16.1.0/24"` | no | Service IP CIDR range |
| `master_ipv4_cidr_block` | string | `"172.16.0.0/28"` | no | Control plane CIDR range |
| `gcp_cidr_range` | string | `"10.128.0.0/20"` | no | VPC subnet CIDR range |
| `gcp_subnetwork_proxy_name` | string | `""` | no | Proxy-only subnet name (for internal LB) |
| `gcp_subnetwork_proxy_cidr_range` | string | `"10.129.0.0/20"` | no | Proxy-only subnet CIDR range |
| `gcp_network_router_name` | string | `""` | no | Cloud Router name (empty = auto-generate) |
| `gcp_network_name` | string | `""` | no | VPC network name (empty = auto-generate) |
| `gcp_subnetwork_name` | string | `""` | no | VPC subnet name (empty = auto-generate) |
| `network_policy` | bool | `true` | no | Enable Kubernetes network policies |
| `ip_ranges_allowed_to_kubeapi` | list(any) | `[]` | no | CIDR ranges authorized to access Kubernetes API |
| `kubernetes_private_cluster_enabled` | bool | `false` | no | Enable private (non-internet-reachable) API endpoint |

---

## Storage (GCS)

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `gcs_bucket_name` | string | `""` | no | Explicit GCS bucket name. Empty string causes auto-generation of a unique name. Must be set explicitly for DR to ensure deterministic naming across regions. |
| `logscale_access_logs_bucket` | string | `""` | no | GCS bucket for access logs |

---

## Service Account

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `logscale_tf_service_account_name` | string | `""` | no | Terraform service account name |
| `terraform_gcp_sa_email` | string | `""` | no | Terraform service account email override |
| `logscale_cluster_k8s_service_account_name` | string | `""` | no | Kubernetes service account name for LogScale pods |
| `manage_terraform_service_account` | bool | `false` | no | Create the Terraform SA (requires IAM admin permissions) |
| `use_existing_gcp_sa` | bool | `true` | no | Use a pre-existing GCP service account for Workload Identity |
| `existing_gcp_sa_name` | string | `""` | no | Existing GCP service account `account_id` field |

---

## Cluster Topology

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `logscale_cluster_type` | string | -- | YES | Cluster topology: `basic`, `dedicated-ui`, or `advanced` |
| `logscale_cluster_size` | string | `"xsmall"` | no | Cluster size: `xsmall`, `small`, `medium`, `large`, `xlarge` |
| `logscale_cluster_k8s_namespace_name` | string | `"log"` | no | Kubernetes namespace for LogScale |
| `humio_cluster_instance_name` | string | `""` | no | HumioCluster custom resource instance name |
| `provision_kafka_servers` | bool | `true` | no | Provision Strimzi-managed Kafka cluster |

---

## Kubernetes Auth

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `use_kubeconfig_auth` | bool | `true` | no | Use kubeconfig file for Kubernetes provider auth |
| `kubeconfig_filepath` | string | `"~/.kube/config"` | no | Path to kubeconfig file |

---

## DR Mode

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `dr` | string | `"active"` | no | DR mode: `"active"` for primary, `"standby"` for secondary. Controls whether LogScale starts in recovery mode and whether GLB/DNS resources are created. |
| `dr_use_dedicated_routing` | bool | `true` | no | Controls service selector on the HumioCluster CR. When `false`, uses generic `app.kubernetes.io/name=humio` selector (all traffic routes to any pod). When `true`, uses pool-specific selectors. Set `false` during promotion Phase 1, then `true` in Phase 2 after all pod types are running. |

---

## DR Remote State

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `primary_remote_state_config` | object({backend, workspace, config}) | `null` | no | Remote state configuration for reading primary cluster state from secondary. Used to retrieve encryption keys, bucket names, and instance group URLs. Only set on secondary (`dr="standby"`). |
| `secondary_remote_state_config` | object({backend, workspace, config}) | `null` | no | Remote state configuration for reading secondary cluster state from primary. Used by GLB module to add secondary backend. Only set on primary (`dr="active"` with `enable_global_lb=true`). |

---

## DR Cross-Region GCS

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `dr_primary_gcs_bucket` | string | `""` | no | Primary cluster's GCS bucket name. Set on secondary to grant cross-region read IAM for recovery. |
| `dr_primary_access_logs_bucket` | string | `""` | no | Primary cluster's access logs bucket name. Set on secondary for cross-region IAM. |

---

## DR Recovery Environment Variables

These variables control the `GCP_RECOVER_FROM_*` environment variables set on the HumioCluster CR when `dr="standby"`. LogScale reads these at startup to initiate recovery from the primary's GCS bucket.

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `gcp_recover_from_region` | string | `""` | no | DEPRECATED. Not used by LogScale for GCS recovery. Retained for backward compatibility. |
| `gcp_recover_from_bucket` | string | `""` | no | Primary's GCS bucket name. Maps to `GCP_RECOVER_FROM_BUCKET` env var on standby. |
| `gcp_recover_from_encryption_key_secret_name` | string | `"gcs-storage-encryption-recovery"` | no | Kubernetes secret name containing the primary's encryption key. Effective default when empty: `dr-secondary-gcs-storage-encryption` (set by the post-install module). |
| `gcp_recover_from_encryption_key_secret_key` | string | `"gcp-storage-encryption-key"` | no | Key within the Kubernetes secret. |
| `gcp_recover_from_replace_region` | string | `""` | no | Region replacement mapping (old/new). Maps to `GCP_RECOVER_FROM_REPLACE_REGION`. Used when primary and secondary are in different regions and GCS paths contain region references. |
| `gcp_recover_from_replace_bucket` | string | `""` | no | Bucket replacement mapping (old/new). Maps to `GCP_RECOVER_FROM_REPLACE_BUCKET`. Used when primary and secondary use different bucket names and GCS paths reference bucket names. |
| `existing_gcs_encryption_key` | string (sensitive) | `""` | no | Explicit GCS encryption key value. Alternative to reading via remote state. If set, used directly instead of fetching from primary's remote state. |

---

## Global Load Balancer

These variables configure the GCP Global HTTP(S) Load Balancer used for health-based DR failover. Only deployed on the primary cluster when `dr="active"` and `enable_global_lb=true`.

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `enable_global_lb` | bool | `false` | no | Enable GLB creation. Must be `true` on primary for DR failover. |
| `enable_glb_named_port` | bool | `null` | no | Configure named port on instance groups. Required on both primary and secondary clusters. |
| `global_lb_secondary_instance_group` | string | `""` | no | URL of secondary cluster's instance group. Added as failover backend. |
| `global_lb_health_check_path` | string | `"/api/v1/status"` | no | HTTP path for health checks. |
| `global_lb_health_check_port` | number | `8080` | no | Port for health checks. |
| `global_lb_health_check_type` | string | `"TCP"` | no | Health check protocol: `HTTP`, `HTTPS`, or `TCP`. |
| `global_lb_primary_capacity` | number | `1.0` | no | Primary backend capacity scaler (0.0 to 1.0). |
| `global_lb_primary_neg_self_link` | string | `""` | no | Primary Network Endpoint Group self link. |
| `global_lb_secondary_neg_self_link` | string | `""` | no | Secondary Network Endpoint Group self link. |
| `global_lb_secondary_capacity` | number | `0.0` | no | Secondary backend capacity scaler. `0.0` means failover-only (no traffic until primary fails). |
| `global_lb_create_cluster_dns` | bool | `true` | no | Create per-cluster DNS A records pointing to individual cluster IPs. |
| `global_lb_secondary_cluster_ip` | string | `""` | no | Secondary cluster's external IP for per-cluster DNS record. |
| `glb_backend_port` | number | `31036` | no | Backend port on instance groups (must match NodePort). |
| `logscale_ui_nodeport` | number | `31036` | no | Fixed NodePort for the LogScale UI Kubernetes service. Must match `glb_backend_port`. |

---

## DNS Failover

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `manage_global_dns` | bool | `true` | no | Manage global DNS failover records. Only effective on primary (`dr="active"`). |
| `global_dns_zone_name` | string | `""` | no | Cloud DNS managed zone name. |
| `global_logscale_hostname` | string | `""` | no | Global hostname for DR failover (resolves to GLB VIP). |
| `primary_logscale_hostname` | string | `""` | no | Primary cluster's dedicated hostname. |
| `secondary_logscale_hostname` | string | `""` | no | Secondary cluster's dedicated hostname. |
| `private_dns_zone_name` | string | `""` | no | Private Cloud DNS zone name for internal resolution. |
| `public_dns_zone_name` | string | `""` | no | Public Cloud DNS zone name for external resolution. |

---

## DR Cloud Function

These variables configure an optional Cloud Function that monitors GLB health checks and automatically scales up the standby cluster's node pools when the primary fails. Requires Pub/Sub for event routing.

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `dr_cloud_function_enabled` | bool | `false` | no | Enable the failover Cloud Function on standby. |
| `dr_cloud_function_target_node_count` | number | `1` | no | Target node count per pool on failover trigger. |
| `dr_cloud_function_timeout` | number | `300` | no | Function execution timeout in seconds. |
| `dr_cloud_function_memory_mb` | number | `256` | no | Function memory allocation in MB. |
| `dr_cloud_function_pre_failover_failure_seconds` | number | `180` | no | Consecutive failure duration in seconds before triggering failover (range: 0-600). Prevents spurious failovers from transient health check failures. |
| `dr_glb_backend_service_name` | string | `""` | no | GLB backend service name. Used as fallback for health status queries when the function cannot determine backend health from Pub/Sub events alone. |

---

## Miscellaneous

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `node_pool_auth_scopes` | list(string) | `["devstorage.read_only", "compute", "logging.write", "monitoring"]` | no | OAuth scopes for GKE node pools. |
| `logscale_gcp_tf_state_bucket` | string | `""` | no | GCS bucket for Terraform state. |
| `logging_service` | string | `"logging.googleapis.com/kubernetes"` | no | GCP logging service for GKE. |
| `monitoring_service` | string | `"monitoring.googleapis.com/kubernetes"` | no | GCP monitoring service for GKE. |
| `maintenance_policy_start_time` | string | `"05:00"` | no | GKE maintenance window start time (UTC). |
| `expected_workspace` | string | `null` | no | Expected Terraform workspace name. If set, `terraform plan` fails when the actual workspace does not match. Safety guard against running in the wrong workspace. |
