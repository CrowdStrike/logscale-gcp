# GCP DR Data Flow -- Encryption Keys, GCS Buckets, Remote State

This document traces the data flow between primary and secondary GCP LogScale clusters
for disaster recovery. It covers encryption key synchronization, GCS bucket naming
and IAM, remote state wiring, and the environment variables that drive LogScale's
recovery process.

---

## 1. Encryption Key Synchronization

LogScale encrypts data at rest in GCS using a symmetric key stored in a Kubernetes
secret. Both the primary and secondary clusters must use the same key so the
secondary can decrypt the primary's snapshots during recovery.

### Flow

```
PRIMARY CLUSTER                         SECONDARY CLUSTER
+---------------------------+          +---------------------------+
| post-install module:      |          | post-install module:      |
|                           |          |                           |
| random_password           |          | Read key from one of:     |
|   .gcp_storage_           |          |   1. existing_gcs_        |
|    encryption_password    |          |      encryption_key var   |
|        |                  |          |   2. primary remote state |
|        v                  |          |      .gcs_storage_        |
| kubernetes_secret         |          |      encryption_key       |
|   "{name}-gcp-storage-    |          |        |                  |
|    encryption-key"        |  remote  |        v                  |
|        |                  |  state   | kubernetes_secret (x2):   |
| Exported as TF output:   |--------->|   a) "{name}-gcp-storage- |
|   gcs_storage_            |          |       encryption-key"     |
|   encryption_key          |          |      (own bucket encrypt) |
|   (sensitive)             |          |   b) "dr-secondary-gcs-   |
+---------------------------+          |       storage-encryption"  |
                                       |      (recovery decrypt)   |
                                       +---------------------------+
```

### Terraform Code Path

**Primary (generates the key):**

1. `modules/kubernetes/post-install/main.tf` creates `random_password.gcp_storage_encryption_password`
   (count = 1 when `dr != "standby"`, length = 64, no special characters)
2. Stores value in `kubernetes_secret.gcp_storage_encryption_key`
   (secret name: `{logscale_cluster_name}-gcp-storage-encryption-key`,
    key: `gcp-storage-encryption-key`)
3. Exports via output `gcp_storage_encryption_key_value` (sensitive)
4. Root `outputs.tf` re-exports as `gcs_storage_encryption_key` for remote state access

**Secondary (imports the key):**

1. `data.terraform_remote_state.primary[0].outputs.gcs_storage_encryption_key` fetches the value
2. `modules/kubernetes/post-install/main.tf` creates two secrets:
   - `kubernetes_secret.gcp_storage_encryption_key` -- uses the imported key for the secondary's
     own bucket encryption (same key as primary ensures data portability)
   - `kubernetes_secret.gcp_dr_storage_encryption_key` -- stores the key under the DR recovery
     secret name for LogScale's `GCP_RECOVER_FROM_ENCRYPTION_KEY` env var

### Resolution Logic (locals.tf)

The key resolution follows a priority chain:

```terraform
# Step 1: Try remote state
remote_gcs_encryption_key = var.primary_remote_state_config == null ? null :
    try(data.terraform_remote_state.primary[0].outputs.gcs_storage_encryption_key, null)

# Step 2: Prefer explicit variable, fall back to remote state
effective_gcs_encryption_key = var.existing_gcs_encryption_key != null ?
    var.existing_gcs_encryption_key :
    local.remote_gcs_encryption_key
```

Priority:
1. `existing_gcs_encryption_key` variable (set directly in tfvars) -- highest priority
2. Remote state output from primary -- automatic discovery
3. `null` -- post-install module generates a new key (primary behavior)

---

## 2. GCS Bucket Naming Strategy

Deterministic bucket naming is critical for DR because:
- The primary must know the secondary's bucket name at deploy time (for cross-region IAM)
- The secondary must know the primary's bucket name to set `GCP_RECOVER_FROM_BUCKET`
- Both must be knowable without requiring the other cluster to exist first

### Naming Patterns (from locals.tf)

**DR deployments** (`is_dr_deployment = true`, i.e., any remote state config is set):

| Cluster Role | Data Bucket | Access Logs Bucket |
|---|---|---|
| Primary (`dr = "active"`) | `dr-primary-{region}-{project_id}` | `logs-pri-{region}-{project_id}` |
| Secondary (`dr = "standby"`) | `dr-secondary-{region}-{project_id}` | `logs-sec-{region}-{project_id}` |

**Non-DR deployments** (`is_dr_deployment = false`):

| Cluster Role | Data Bucket | Access Logs Bucket |
|---|---|---|
| Primary | `{infrastructure_prefix}-{region}-{project_id}` | `logs-{infrastructure_prefix}-{region}-{project_id}` |
| Secondary | `{infrastructure_prefix}-secondary-{region}-{project_id}` | `logs-{infrastructure_prefix}-sec-{region}-{project_id}` |

**Override:** Set `gcs_bucket_name` (or `dr_primary_gcs_bucket`) explicitly to use an
exact name instead of the generated pattern.

### Cross-Region IAM Flow

```
PRIMARY                                   SECONDARY
+------------------------+               +------------------------+
| GCS bucket:            |               | GCS bucket:            |
|   dr-primary-          |               |   dr-secondary-        |
|   us-west1-proj123     |               |   us-east1-proj123     |
|                        |               |                        |
| SA: wl-identity@...    |               | SA: wl-identity@...    |
|   roles/storage.admin  |               |   roles/storage.admin  |
|   roles/storage.       |               |   roles/storage.       |
|   objectUser           |               |   objectUser           |
+------------------------+               +------------------------+
                                                |
                                                | IAM bindings on PRIMARY bucket:
                                                |   storage.legacyBucketReader
                                                |   storage.objectViewer
                                                |
                                          (grants secondary SA read
                                           access to primary bucket)
```

These IAM bindings are created by `modules/gcp/gke/storage.tf`:

```terraform
resource "google_storage_bucket_iam_member" "dr_cross_region_access" {
  count  = var.dr == "standby" && var.dr_primary_gcs_bucket != "" ? 1 : 0
  bucket = var.dr_primary_gcs_bucket     # primary's bucket name
  role   = "roles/storage.legacyBucketReader"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}

resource "google_storage_bucket_iam_member" "dr_cross_region_object_access" {
  count  = var.dr == "standby" && var.dr_primary_gcs_bucket != "" ? 1 : 0
  bucket = var.dr_primary_gcs_bucket
  role   = "roles/storage.objectViewer"
  member = module.gcs_workload_identity.gcp_service_account_fqn
}
```

The `dr_primary_gcs_bucket` value can come from:
1. Explicit tfvars setting
2. Remote state lookup (via `effective_dr_peer_gcs_bucket` local in root `locals.tf`)
3. `gcp_recover_from_bucket` fallback

---

## 3. Remote State Configuration

### Secondary reads primary's outputs

```hcl
# In secondary's tfvars:
primary_remote_state_config = {
  backend   = "gcs"          # or "s3" for MinIO in deployment
  workspace = "default"
  config = {
    bucket = "primary-tf-state-bucket"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}
```

### Primary reads secondary's outputs (for GLB only)

```hcl
# In primary's tfvars (only when enable_global_lb = true):
secondary_remote_state_config = {
  backend   = "gcs"
  workspace = "default"
  config = {
    bucket = "secondary-tf-state-bucket"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}
```

### Data sources (data-source.tf)

```terraform
data "terraform_remote_state" "primary" {
  count   = var.primary_remote_state_config != null ? 1 : 0
  backend = var.primary_remote_state_config.backend
  workspace = var.primary_remote_state_config.workspace
  config    = var.primary_remote_state_config.config
}

data "terraform_remote_state" "secondary" {
  count   = var.secondary_remote_state_config != null ? 1 : 0
  backend = var.secondary_remote_state_config.backend
  workspace = var.secondary_remote_state_config.workspace
  config    = var.secondary_remote_state_config.config
}
```

### What remote state provides

| Output | Consumed By | Purpose |
|---|---|---|
| `gcs_bucket_id` | Secondary | Discover primary's bucket name for `GCP_RECOVER_FROM_BUCKET` |
| `gcs_bucket_region` | Secondary | Build `GCP_RECOVER_FROM_REPLACE_REGION` path translation |
| `gcs_storage_encryption_key` | Secondary | Encryption key sync (sensitive) |
| `instance_group_urls` | Primary (GLB) | Add secondary as backend target in load balancer |
| `gce_ingress_ip_address` | Primary (GLB) | Secondary's static IP for per-cluster DNS A record |
| `cluster_location` | Primary (GLB) | Secondary's region for backend service config |
| `global_lb_backend_service_name` | Secondary (Cloud Function) | GLB backend name for health-based failover alert |
| `global_dns_zone_name` | Secondary | DNS zone name discovery (avoids duplicating in tfvars) |
| `cluster_name` | Secondary | Used in DR recovery replace patterns |
| `primary_health_check_id` | Secondary (Cloud Function) | Reuse primary's health check instead of creating duplicate |
| `gcs_encryption_key_secret_name` | Secondary | K8s secret name for recovery encryption key |

---

## 4. DR Environment Variables on Standby

When `dr = "standby"`, the root `main.tf` builds `user_logscale_envvars` that get
injected into the HumioCluster CR's pod spec. These are consumed by LogScale's
recovery subsystem when the standby cluster starts or is promoted.

### Base variables (all clusters)

| Variable | Value | Source |
|---|---|---|
| `GCP_STORAGE_WORKLOAD_IDENTITY` | `"true"` | Hardcoded |
| `GCP_STORAGE_BUCKET` | Secondary's own bucket name | `module.gke.gke_storage_bucket` |
| `ENABLE_ALERTS` | `"false"` | Set false when `dr == "standby"` |
| `GCP_STORAGE_ENCRYPTION_KEY` | From K8s secret | `secretKeyRef` to post-install encryption secret |

### Recovery variables (standby only)

| Variable | Value | Source |
|---|---|---|
| `GCP_RECOVER_FROM_BUCKET` | Primary's bucket name | `local.final_gcp_recover_from_bucket` (remote state or tfvars) |
| `GCP_RECOVER_FROM_WORKLOAD_IDENTITY` | `"true"` | Hardcoded |
| `GCP_RECOVER_FROM_REPLACE_REGION` | `"{primary-region}/{secondary-region}"` | `local.final_gcp_recover_from_replace_region` |
| `GCP_RECOVER_FROM_REPLACE_BUCKET` | `"{primary-bucket}/{secondary-bucket}"` | `local.final_gcp_recover_from_replace_bucket` or auto-constructed |
| `GCP_RECOVER_FROM_ENCRYPTION_KEY` | From K8s secret | `secretKeyRef` to DR recovery encryption secret |

### Notable design decisions

- **`GCP_RECOVER_FROM_REGION` is NOT set.** GCS buckets are globally addressable —
  no region is needed for cross-region access (unlike S3). LogScale ignores this
  variable for the GCS bucket provider.

- **`GCP_RECOVER_FROM_REPLACE_REGION` IS set** despite the above. This is for path
  translation in stored snapshot references, not for bucket access. LogScale rewrites
  paths like `us-west1/bucket/object` to `us-east1/bucket/object`.

- **`ALLOW_KAFKA_RESET_UNTIL_TIMESTAMP_MS` is NOT required.** LogScale automatically
  enables `allowKafkaReset` when `bucketStorageRecoverFrom` is configured.

- **`ENABLE_ALERTS` is `"false"` on standby** to prevent the standby cluster from
  firing duplicate alerts before it is promoted. On promotion (changing `dr` from
  `"standby"` to `"active"`), this flips to `"true"`.

### secretKeyRef resolution

The encryption key env vars use `secretKeyRef` rather than inline values to avoid
exposing sensitive keys in the HumioCluster CR or Terraform state. The references:

```
GCP_STORAGE_ENCRYPTION_KEY:
  secretKeyRef:
    name: {logscale_cluster_name}-gcp-storage-encryption-key
    key:  gcp-storage-encryption-key

GCP_RECOVER_FROM_ENCRYPTION_KEY:
  secretKeyRef:
    name: dr-secondary-gcs-storage-encryption  (default, configurable)
    key:  gcp-storage-encryption-key       (default, configurable)
```

Both secrets are created by `modules/kubernetes/post-install`. On standby, both
contain the same key value (imported from primary), but they are separate secrets
to maintain the contract that LogScale expects different secret names for own-bucket
vs recovery-bucket encryption.

---

## 5. DR State Impact Summary

How each component behaves based on the `dr` variable value.

| Component | `dr = "active"` (Primary) | `dr = "standby"` (Secondary) |
|---|---|---|
| **GCS Bucket** | Own bucket, full R/W | Own bucket (R/W) + read-only on primary's bucket |
| **Encryption Key** | Generated (random, 64 chars) | Imported from primary (remote state or explicit) |
| **HumioCluster Alerts** | Enabled (`ENABLE_ALERTS=true`) | Disabled (`ENABLE_ALERTS=false`) |
| **Recovery Env Vars** | Not set | Set (`GCP_RECOVER_FROM_*`) |
| **Global Load Balancer** | Created (if `enable_global_lb=true`) | Not created |
| **Cloud Function** | Not created | Created (if `dr_cloud_function_enabled=true`) |
| **DNS Failover (WRR)** | Manages global CNAME records | No global DNS management |
| **DNS Failover (A record)** | Creates per-cluster A record | Creates per-cluster A record |
| **Node Pool Routing** | Dedicated pool selectors (default) | Configurable via `dr_use_dedicated_routing` |
| **Workload Identity** | Binds all 3 K8s SAs | Binds all 3 K8s SAs |
| **Cross-Region IAM** | Not created (no need) | Grants read on primary's bucket |
| **Access Logs Bucket** | Own logs bucket | Own logs bucket (separate from primary) |

### Node Pool Routing Detail

The `dr_use_dedicated_routing` variable controls how the NodePort service selector
targets pods. This is relevant during DR promotion:

| Phase | `dr_use_dedicated_routing` | Service Selector | Behavior |
|---|---|---|---|
| Normal operation | `true` (default) | Pool-specific: `humio.com/node-pool: {prefix}-ui` | Traffic goes to dedicated UI pods |
| DR promotion phase 1 | `false` | Generic: `app.kubernetes.io/name: humio` | Traffic goes to ANY humio pod (zero-downtime during scale-up) |
| DR promotion phase 2 | `true` | Pool-specific | Traffic shifts to newly scaled UI/Ingest pods |

---

## 6. Failover Automation (Cloud Function)

The DR failover Cloud Function (`dr-failover-function` module) provides automated
failover when the primary cluster becomes unhealthy.

### Trigger Chain

```
Primary cluster goes down
        |
        v
Uptime Check fails (every 60s, checking /api/v1/status on primary FQDN)
        |
        v
Alert Policy fires (after 60s sustained failure)
        |
        v
Notification Channel publishes to Pub/Sub topic ({cluster}-dr-alerts)
        |
        v
Cloud Function triggered (failover_handler)
        |
        v
Function validates:
  1. Primary has been failing for >= pre_failover_failure_seconds (default 180s)
  2. Cooldown period has not elapsed since last failover
        |
        v
Function scales GKE node pool to target_node_count
Function patches HumioCluster CR to enable standby promotion
```

### GLB Health-Based Trigger (Alternative)

When GLB is enabled, a second alert policy monitors the GLB backend service directly:

```
GLB detects primary backend unhealthy (via health check)
        |
        v
Alert on: 5xx responses OR zero 200 responses for 60s
        |
        v
Same Pub/Sub -> Cloud Function chain as above
```

This provides faster detection than the uptime check because the GLB health check
runs at the infrastructure level (default interval: configurable via
`health_check_interval_sec`).

### Function Configuration

| Parameter | Default | Description |
|---|---|---|
| `function_timeout` | 300s | Max execution time |
| `function_memory_mb` | 256 Mi | Memory allocation |
| `target_node_count` | 1 | Nodes to scale to on failover |
| `pre_failover_failure_seconds` | 180s | Minimum consecutive failure before acting |
| `max_retries` | Configurable | Retry count for GKE API calls |
| `base_delay_seconds` | Configurable | Initial retry backoff |
| `failover_cooldown_seconds` | Configurable | Minimum time between failover events |

---

## 7. Remote State Bootstrapping Order

DR deployments must be applied in a specific order because each cluster
reads the other's state.

### Initial Deployment (No GLB)

```
Step 1: Deploy PRIMARY cluster
  - No remote state config needed
  - Generates encryption key
  - Creates GCS bucket with deterministic name
  - Exports outputs to state backend

Step 2: Deploy SECONDARY cluster
  - Set primary_remote_state_config pointing to primary's state
  - Reads: encryption key, bucket name, bucket region, DNS zone
  - Creates own bucket + cross-region IAM on primary's bucket
  - Sets GCP_RECOVER_FROM_* env vars on HumioCluster
```

### Initial Deployment (With GLB)

```
Step 1: Deploy PRIMARY cluster
  - enable_global_lb = true
  - No secondary_remote_state_config yet (secondary doesn't exist)
  - GLB created with primary backend only

Step 2: Deploy SECONDARY cluster
  - primary_remote_state_config set
  - enable_glb_named_port = true
  - Exports instance_group_urls via state

Step 3: Re-apply PRIMARY cluster
  - Add secondary_remote_state_config (points to secondary's state)
  - GLB picks up secondary's instance groups as second backend
  - Primary functions correctly with one backend during steps 1-2
```

---

## 8. Variable Cross-Reference

Quick reference for which variables feed into which components.

### Variables that affect DR behavior

| Variable | Used By | Effect |
|---|---|---|
| `dr` | All modules | Master switch: `"active"` or `"standby"` |
| `dr_use_dedicated_routing` | `module.logscale` | Service selector strategy during promotion |
| `primary_remote_state_config` | Root data sources | Enables secondary -> primary state reading |
| `secondary_remote_state_config` | Root data sources | Enables primary -> secondary state reading (GLB) |
| `dr_primary_gcs_bucket` | `module.gke`, locals | Explicit primary bucket name override |
| `existing_gcs_encryption_key` | `module.kubernetes_post_install` | Direct key injection (skips remote state) |
| `gcp_recover_from_bucket` | Root locals | Fallback primary bucket name for recovery |
| `gcp_recover_from_replace_region` | Root locals | Explicit region replacement pattern |
| `gcp_recover_from_replace_bucket` | Root locals | Explicit bucket replacement pattern |
| `gcp_recover_from_encryption_key_secret_name` | `module.kubernetes_post_install` | K8s secret name for recovery key |
| `gcp_recover_from_encryption_key_secret_key` | `module.kubernetes_post_install` | Key within K8s secret |
| `enable_global_lb` | `module.global_lb`, `module.dns_failover`, `module.kubernetes_post_install` | GLB vs DNS failover |
| `enable_glb_named_port` | `module.kubernetes_post_install` | Named port on instance groups for GLB |
| `dr_cloud_function_enabled` | `module.dr_failover_function` | Automated failover function |
| `manage_global_dns` | `module.dns_failover` | Global WRR CNAME management |

### Deprecated variables (kept for backwards compatibility)

| Variable | Reason |
|---|---|
| `gcp_recover_from_region` | GCS does not use region for bucket access. LogScale returns `"region-not-set"`. |
