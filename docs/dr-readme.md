# GCP LogScale Disaster Recovery Guide

This guide covers setting up, verifying, and operating disaster recovery (DR) for LogScale on Google Kubernetes Engine (GKE). It assumes familiarity with Terraform, GKE, and the LogScale platform.

---

## Overview

The DR architecture uses an **active-standby** model across two GCP regions:

- The **primary** cluster handles all production traffic (ingest, search, UI).
- The **secondary** cluster runs a minimal-footprint standby: Kafka brokers, cert-manager, and the humio-operator deployment (scaled to 0 replicas). No LogScale pods run on standby — the operator being at zero replicas prevents any pod creation regardless of the HumioCluster CR spec.
- Failover can be triggered three ways:
  1. **Automated (GLB + Cloud Function)** — Uptime check detects primary failure, Cloud Function scales operator and flips GLB capacity. Tested.
  2. **Manual (GLB)** — Operator scaled to 0 on primary, GLB capacity_scaler flipped manually via gcloud or Terraform. Tested.
  3. **DNS WRR routing** — Cloud DNS weighted round-robin with manual weight change. Untested.
- Encryption keys are synchronized to the secondary cluster via **Terraform remote state** references.
- The secondary cluster has **read-only cross-region access** to the primary's GCS bucket for snapshot recovery. This applies when primary bucket data is NOT replicated to the secondary bucket (e.g., via GCS Transfer Service or dual-region storage). If replication is configured, set `GCP_RECOVER_FROM_REPLACE_BUCKET` to rewrite segment paths to the local copy instead. Cross-region read path is tested; replicated bucket path is untested.
- Promotion from standby to active uses a **two-phase pool routing switch** to avoid traffic blackhole during service selector changes. This does NOT guarantee zero data loss — events in flight during the failover window (30-60s GLB detection + CF trigger delay) may be lost. RPO depends on client-side retry and buffering capabilities.

---

## Architecture

```
Region A (Primary)                    Region B (Secondary)
+-----------------------+             +-----------------------+
| GKE Cluster           |             | GKE Cluster           |
| +-- Digest pods       |             | +-- Kafka brokers     |
| +-- UI pods           |             | +-- cert-manager      |
| +-- Ingest pods       |             | +-- humio-operator    |
| +-- Kafka brokers     |             |     (0 replicas)      |
| +-- cert-manager      |             |                       |
|                       |             | NOT running:          |
|                       |             | - LogScale pods       |
|                       |             |   (epoch conflict if  |
|                       |             |    started prematurely)|
|                       |             |                       |
| GCS Bucket (R/W)      |             | GCS Bucket (own, R/W) |
| dr-primary-...        |             | dr-secondary-...      |
+-----------------------+             +-----------------------+
         |                                     |
         |  Without bucket replication:        |
         +--- read-only cross-region access ---+
         |    (secondary reads primary bucket) |
         |                                     |
         |  With bucket replication:           |
         |    (secondary reads local copy,     |
         |     set GCP_RECOVER_FROM_REPLACE_   |
         |     BUCKET to rewrite paths)        |
         |                                     |
         +------ Global LB (health check) ----+
         +------ Cloud DNS (failover) --------+
```

**Key points:**

- The secondary cluster's GCS bucket is its own; it does not write to the primary's bucket.
- The secondary reads the primary's bucket only during recovery (snapshot restore).
- The GLB health check determines which backend receives traffic. When the primary fails, traffic shifts to the secondary.
- Cloud DNS failover routing provides an alternative (or complementary) mechanism for DNS-level redirection.

---

## Prerequisites

| Requirement | Details |
|---|---|
| GCP projects | Single project with resources in two different regions (tested). Two separate projects are supported but untested — cross-project IAM for GCS, GLB, and service account impersonation requires additional role bindings not covered here. |
| Terraform state backend | GCS bucket (or equivalent) accessible from both regions |
| Cloud DNS zone | A managed zone for the global hostname used by both clusters (see below) |
| LogScale license | The same license key must be used on both primary and secondary |
| Service accounts | Service accounts in both regions with the required IAM roles (GKE, GCS, DNS, Compute) |
| Terraform and gcloud CLI | Installed and authenticated for both regions |

### Create the Cloud DNS Managed Zone

The DR module uses `data.google_dns_managed_zone` to look up the zone at plan time. This data source runs unconditionally, so the zone **must exist before any `terraform plan` or `terraform apply`** on a DR-enabled worker, even for steps that do not involve DNS.

```bash
gcloud dns managed-zones create <zone-name> \
  --dns-name="<your-domain>." \
  --description="DR failover zone" \
  --project=<project-id>
```

Set `global_dns_zone_name` in the worker config to match:

```yaml
global_dns_zone_name: "<zone-name>"
```

---

## Stage 1: DR Configuration Setup

### 1.1 Plan Your Naming

Choose deterministic, region-scoped names for all resources. This avoids collisions and makes cross-region references unambiguous.

```
Primary:
  Region:                us-central1
  Infrastructure prefix: logscale-primary
  GCS bucket:            logscale-primary-us-central1-<project-id>

Secondary:
  Region:                us-west1
  Infrastructure prefix: logscale-secondary
  GCS bucket:            logscale-secondary-us-west1-<project-id>
```

> **Note:** Replace `<project-id>` with your actual GCP project ID. Bucket names must be globally unique.

---

### 1.2 Deploy Primary Cluster

Create `primary.tfvars`:

```hcl
project_id            = "your-project"
region                = "us-central1"
infrastructure_prefix = "logscale-primary"
dr                    = "active"
logscale_cluster_type = "advanced"
logscale_cluster_size = "small"

# Deterministic bucket naming
gcs_bucket_name = "logscale-primary-us-central1-your-project"

# Global Load Balancer (optional, for health-based failover)
enable_global_lb      = true
enable_glb_named_port = true

# DNS
manage_global_dns           = true
global_dns_zone_name        = "your-dns-zone"
global_logscale_hostname    = "logscale"
primary_logscale_hostname   = "dr-primary"
secondary_logscale_hostname = "dr-secondary"
public_dns_zone_name        = "your-public-dns-zone"
public_url                  = "logscale.yourdomain.com"

# Cross-region: primary needs to know secondary's bucket name
dr_primary_gcs_bucket = "logscale-secondary-us-west1-your-project"

# Versions (same on both clusters)
humio_operator_chart_version = "0.29.2"
humio_operator_version       = "0.29.2"
logscale_image_version       = "1.228.1"
# ... (all other version variables)
```

Deploy in targeted order:

```bash
terraform init
terraform apply -target=module.vpc
terraform apply -target=module.gke
# ... (continue with remaining modules per the setup guide)
terraform apply -target=module.global_lb          # GLB for DR
terraform apply -target=module.dns_failover       # DNS records
```

> **Important:** Deploy modules in dependency order. The GLB and DNS modules depend on the GKE cluster and its services being ready.

---

### 1.3 Deploy Secondary (Standby) Cluster

Create `secondary.tfvars`:

```hcl
project_id            = "your-project"
region                = "us-west1"
infrastructure_prefix = "logscale-secondary"
dr                    = "standby"
logscale_cluster_type = "advanced"   # MUST match primary — cost savings come from operator at 0 replicas, not cluster type
logscale_cluster_size = "xsmall"

# Deterministic bucket naming
gcs_bucket_name = "logscale-secondary-us-west1-your-project"

# GLB named port (required so primary GLB can route to secondary)
enable_glb_named_port = true

# Remote state: read primary's outputs for encryption key sync
primary_remote_state_config = {
  backend   = "gcs"
  workspace = "default"
  config = {
    bucket = "your-tf-state-bucket"
    prefix = "logscale/gcp/primary/terraform/tf.state"
  }
}

# Recovery configuration
dr_primary_gcs_bucket          = "logscale-primary-us-central1-your-project"
gcp_recover_from_bucket        = "logscale-primary-us-central1-your-project"
gcp_recover_from_replace_region = "us-central1/us-west1"
# gcp_recover_from_replace_bucket: intentionally NOT set.
# Only set if bucket data is replicated to secondary (e.g., GCS Transfer Service).
# Without replication, LogScale reads historical data from primary bucket (cross-region, readOnly)
# and writes new data to secondary bucket.

# Cloud Function for automated failover (optional)
dr_cloud_function_enabled                      = true
dr_cloud_function_target_node_count            = 2
dr_cloud_function_pre_failover_failure_seconds = 180

# Versions (MUST match primary)
humio_operator_chart_version = "0.29.2"
humio_operator_version       = "0.29.2"
logscale_image_version       = "1.228.1"
# ... (same as primary)

public_url = "logscale.yourdomain.com"
```

Deploy in targeted order:

```bash
terraform init
terraform apply -target=module.vpc
terraform apply -target=module.gke
# ... (targeted deployment per the setup guide)
terraform apply -target=module.dr_failover_function  # Cloud Function
```

### GLB Backend Registration

The standby cluster self-registers its instance groups into the primary's GLB
backend service on first deploy (via `terraform_data.glb_self_register`). No
primary redeploy is required.

Verify both backends are registered after standby deploy:

```bash
gcloud compute backend-services get-health <BACKEND_SERVICE_NAME> \
  --global --format='table(status.healthStatus[].ipAddress,status.healthStatus[].healthState)'
# Expected: 2+ IPs (primary HEALTHY, standby UNHEALTHY — standby has no LogScale pods)
```

If only one backend appears, check that `enable_glb_named_port = true` and
`primary_remote_state_config` are set on the standby worker.

Similarly, after a **standby-to-active-to-standby round-trip** (e.g., DR test
followed by failback), the encryption key recovery secret may be empty. Verify:

```bash
# On STANDBY — must NOT be empty (SHA256 of empty = e3b0c44298fc...)
kubectl get secret <RECOVERY_SECRET> -n log \
  -o jsonpath='{.data.gcp-storage-encryption-key}' | base64 -d | shasum -a 256
```

If the hash is `e3b0c44298fc1c149afbf4c8996fb924...`, the key is empty and DR
recovery will fail. Redeploy the standby to re-read the primary's encryption
key from remote state.

---

## Stage 2: Verification

After deploying both clusters, verify the following before considering DR operational.

> **Detailed checklist:** See [dr-postinstall-checklist.md](dr-postinstall-checklist.md) for
> step-by-step commands with expected outputs, including how to test remote state access
> from a debug pod on the mother cluster. For interactive testing with state tracking,
> use the HTML checklist: `manual-test-checklist.html` (select the `dr-standby` scenario).

### 2.1 Encryption Key Sync

The secondary cluster must have the same storage encryption key as the primary. Without this, snapshot recovery will fail silently.

The primary stores its key in `<INFRA_PREFIX>-gcp-storage-encryption-key`. The standby
stores a copy in a recovery secret whose name is configured by
`gcp_recover_from_encryption_key_secret_name` (common names:
`gcs-storage-encryption-recovery` or `dr-secondary-gcs-storage-encryption`).

```bash
# On PRIMARY
kubectl get secret <INFRA_PREFIX>-gcp-storage-encryption-key \
  -n log -o jsonpath='{.data.gcp-storage-encryption-key}' | base64 -d | shasum -a 256

# On STANDBY — find the recovery secret name first:
kubectl get secrets -n log | grep -iE 'recovery|dr.*encrypt'
# Then hash it:
kubectl get secret <RECOVERY_SECRET> \
  -n log -o jsonpath='{.data.gcp-storage-encryption-key}' | base64 -d | shasum -a 256

# Both SHA256 hashes MUST match. If not, re-run terraform apply on the secondary.
```

### 2.2 Cross-Region GCS Access

The secondary cluster's service account must have read access to the primary's GCS bucket.

```bash
# From SECONDARY cluster's service account
gcloud storage ls gs://logscale-primary-us-central1-your-project/ \
  --impersonate-service-account=<secondary-sa>@<project>.iam.gserviceaccount.com
```

If access is denied, verify IAM bindings and re-run `terraform apply -target=module.gke` on the secondary.

### 2.3 Workload Identity

Confirm that the Kubernetes service account on the secondary is annotated with the correct GCP service account.

```bash
# On SECONDARY
kubectl get sa <humio-sa> -n log \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
# Should output the GCP SA email (e.g., logscale-secondary@your-project.iam.gserviceaccount.com)
```

### 2.4 Node Pool Topology

```bash
# PRIMARY (should have all pools: digest, ui, ingest, kafka)
gcloud container node-pools list --cluster=<primary-cluster> --region=us-central1

# SECONDARY (same GKE node pools as primary — cost savings from operator at 0, not fewer pools)
gcloud container node-pools list --cluster=<secondary-cluster> --region=us-west1
```

### 2.5 HumioCluster State

```bash
# PRIMARY
kubectl get humiocluster -n log -o yaml | grep -A5 'nodePools'
# Should show dedicated pool definitions for each node role

# SECONDARY
kubectl get humiocluster -n log -o yaml | grep -A5 'nodePools'
# Should show nodePools with nodeCount=1 per pool (ui, ingest-only).
# Pods are NOT created because operator is at 0 replicas.
```

### 2.6 Recovery Environment Variables

On the **standby** cluster, verify that recovery environment variables are configured
in the HumioCluster CR spec (pods are not running on standby, so verify via CR not pod exec):

```bash
kubectl get humiocluster -n log -o jsonpath='{.items[0].spec.environmentVariables}' | \
  python3 -m json.tool | grep -A1 GCP_RECOVER
```

Expected output (values will match your worker config):

```
GCP_RECOVER_FROM_BUCKET=<primary-bucket-name>
GCP_RECOVER_FROM_WORKLOAD_IDENTITY=true
GCP_RECOVER_FROM_REPLACE_REGION=<primary-region>/<standby-region>
```

`GCP_RECOVER_FROM_REPLACE_BUCKET` should only be present if bucket replication is configured.
If not set, LogScale reads historical data cross-region from the primary bucket (readOnly).

What these do:
- `GCP_RECOVER_FROM_BUCKET`: Primary's GCS bucket — standby reads snapshots from here.
- `GCP_RECOVER_FROM_WORKLOAD_IDENTITY=true`: Use standby's own Workload Identity SA for cross-bucket access.
- `GCP_RECOVER_FROM_REPLACE_REGION`: Find/replace pattern for region references in stored metadata during recovery. Format: `find/replace`.
- `GCP_RECOVER_FROM_REPLACE_BUCKET`: Find/replace pattern for bucket name references in stored metadata.

Also verify `GCP_RECOVER_FROM_REGION` is **NOT** set (GCS does not need it):

```bash
kubectl exec -it $POD -n log -- env | grep GCP_RECOVER_FROM_REGION || echo 'NOT SET (correct)'
```

### 2.7 Global Load Balancer

```bash
# Check GLB backend health
gcloud compute backend-services get-health <backend-service-name> --global

# Check DNS resolution
dig +short logscale.yourdomain.com
dig +short dr-primary.yourdomain.com
dig +short dr-secondary.yourdomain.com
```

All three hostnames should resolve. The global hostname should point to the primary's IP while the primary is healthy.

### 2.8 Cloud Function (if enabled)

```bash
gcloud functions describe <function-name> --region=us-west1 --gen2
```

Verify the function is deployed and its environment variables reference the correct secondary cluster and node pool targets.

---

## Stage 3: Failover Testing

Test failover **before** relying on DR in production. The following steps simulate a primary failure and walk through promotion.

### 3.1 Simulate Primary Failure

Choose one approach:

**Option A -- Scale down primary LogScale:**

```bash
kubectl scale deployment humio-operator -n log --replicas=0 --context=<primary>
```

**Option B -- Cordon all primary nodes:**

```bash
kubectl cordon --all --context=<primary>
```

### 3.2 Observe Failover

The failover mechanism depends on your configuration:

| Mechanism | Behavior |
|---|---|
| **Global Load Balancer** | Health check fails on primary. GLB routes traffic to secondary within 30-60 seconds. |
| **Cloud Function** | Consecutive health check failures exceed `dr_cloud_function_pre_failover_failure_seconds` (default: 180s). Function triggers and scales up standby node pools. |
| **DNS only** | Manual intervention required. Update DNS records to point to secondary. |

### 3.3 Promote Secondary to Active

Promotion uses a two-phase approach to avoid a traffic blackhole during the transition.

**Why two phases?** The `dr_use_dedicated_routing` variable controls how the NodePort service selects which pods receive traffic:

| Value | Service selector | Effect |
|---|---|---|
| `false` | Broad label (`app.kubernetes.io/name: humio`) | Any running LogScale pod can serve any request — ingest, search, or UI |
| `true` | Pool-specific labels (`k8s-app: logscale-ingest`, etc.) | Each traffic type routes only to pods on its designated node pool |

If you set `true` immediately, but some node pools haven't finished scaling yet, the service has zero matching backends for that traffic type — requests are dropped. Phase 1 avoids this by accepting traffic on whatever pods are ready.

**Phase 1 -- Broad routing (safe while node pools scale up):**

Update `secondary.tfvars`:

```hcl
dr                       = "active"
dr_use_dedicated_routing = false   # any pod serves any traffic type while pools scale
# logscale_cluster_type remains "advanced" — do NOT change it
```

Apply:

```bash
terraform apply
```

This creates all node pools and starts LogScale pods. Because the service selector is broad, traffic flows to whichever pods come up first — no blackhole even if some pools are still scaling.

> **Important:** The `gcp_recover_from_*` variables must remain in the secondary's tfvars during and after promotion. The recovery environment variables (`GCP_RECOVER_FROM_BUCKET`, etc.) are injected whenever `gcp_recover_from_bucket` is set, regardless of the `dr` value. This ensures LogScale can recover data from the primary's GCS bucket during promotion.
>
> **WARNING: NEVER remove `gcp_recover_from_*` variables after promotion.** Removing them changes the pod spec hash, causing the operator to recreate pods with new PVCs — resulting in DATA LOSS. These variables are harmlessly ignored after initial recovery (LogScale reads them once at snapshot load).

**Phase 2 -- Dedicated routing (after all pools are healthy):**

Once all node pools are running and pods are scheduled on their designated pools:

Update `secondary.tfvars`:

```hcl
dr_use_dedicated_routing = true   # ingest→ingest pods, search→UI pods, etc.
```

Apply:

```bash
terraform apply
```

This switches to pool-specific selectors matching the production topology. Only do this after confirming all pools have healthy pods (`kubectl get pods -n log -o wide`).

### 3.4 Restore Primary (After Testing)

After verifying the secondary is serving traffic correctly:

1. Uncordon primary nodes (if you used Option B) or scale the operator back up (Option A).
2. Re-run `terraform apply` on the primary to restore it to `active` state.
3. Update DNS or GLB configuration to shift traffic back to the primary.
4. Demote the secondary back to `standby` by reverting `secondary.tfvars` to the original values.

---

## Failover Timing

| Phase | Duration |
|---|---|
| GLB detects primary failure | 30-60 seconds |
| Cloud Function triggers (if enabled) | ~3 minutes (configurable via `dr_cloud_function_pre_failover_failure_seconds`) |
| Standby LogScale pod starts | 2-5 minutes |
| Promotion Phase 1 (generic routing) | 5-10 minutes |
| Promotion Phase 2 (dedicated routing) | 2-5 minutes |
| New node pools scale up | 5-15 minutes |
| **Total RTO (Recovery Time Objective)** | **15-35 minutes** |

> **Note:** The RTO range depends on cluster size, node pool scale-up time, and whether the Cloud Function pre-scales standby nodes before manual promotion.

---

## Troubleshooting

| Problem | Likely Cause | Resolution |
|---|---|---|
| Secondary cannot read primary's snapshots | Encryption key mismatch | Verify remote state config on secondary. Re-run `terraform apply` on secondary to re-sync the key. |
| GCS access denied on secondary | Missing cross-region IAM bindings | Run `terraform apply -target=module.gke` on secondary to re-apply IAM bindings. |
| Cloud Function not triggering | Failure threshold not reached | Check `dr_cloud_function_pre_failover_failure_seconds` (default 180s = 3 minutes of consecutive failures required). |
| GLB health check failing on a healthy cluster | NodePort service missing or misconfigured | Verify the NodePort service exists: `kubectl get svc -n log \| grep NodePort`. Re-apply the LogScale module if missing. |
| Promotion stuck after Phase 1 | Routing flag misconfigured | Ensure `dr_use_dedicated_routing = false` for Phase 1 and `true` for Phase 2. Apply each phase separately. |
| Old or missing data after failover | Bucket mapping incorrect | Verify `GCP_RECOVER_FROM_REPLACE_BUCKET` has the correct `old-bucket/new-bucket` mapping. The format is `<primary-bucket>/<secondary-bucket>`. |
| Missing repos after promotion | Recovery env vars not on pods | Verify `GCP_RECOVER_FROM_BUCKET` is set on LogScale pods: `kubectl exec -it <pod> -n log -- env \| grep GCP_RECOVER`. If missing, ensure `gcp_recover_from_bucket` is set in tfvars and re-apply. Recovery vars are injected whenever the bucket is configured, regardless of `dr` value. |
| DNS not resolving to secondary after failover | DNS TTL propagation delay | Wait for TTL expiry. Use `dig +trace` to verify propagation. For faster cutover, set low TTLs (60s) before testing. |
| Node pools not scaling during promotion | Insufficient quota in secondary region | Check GCE quotas in the secondary region (`gcloud compute regions describe <region>`). Request increases before DR testing. |

---
---

# Appendix: Initial Deployment

The sections below cover initial GKE cluster deployment, authentication, and general operations. For DR-specific configuration, refer to the stages above.

## Prerequisites

Before deploying, ensure the following are in place:

**GCP Project with Required APIs Enabled**

Enable these APIs in your GCP project:

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  dns.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  cloudfunctions.googleapis.com \
  iap.googleapis.com \
  cloudresourcemanager.googleapis.com
```

**Tools**

| Tool | Minimum Version | Purpose |
|---|---|---|
| Terraform | >= 1.1.0 | Infrastructure provisioning |
| gcloud CLI | latest | GCP authentication and cluster access |
| kubectl | >= 1.28 | Kubernetes cluster management |
| helm | >= 3.x | Used internally by Terraform providers |

**Infrastructure**

- A GCS bucket for Terraform remote state (see [Backend Configuration](#backend-configuration))
- A Cloud DNS managed zone (see [Create the Cloud DNS Managed Zone](#create-the-cloud-dns-managed-zone) above)
- A LogScale license (community or enterprise)

---

## Authentication

### Option A: User Credentials (Local Development)

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>
```

### Option B: Service Account (CI/CD Pipelines)

The Terraform execution identity (user or service account) requires the following IAM roles on the project:

| Role | Purpose |
|---|---|
| `roles/container.admin` | GKE cluster and node pool management |
| `roles/storage.admin` | GCS bucket creation and lifecycle management |
| `roles/iam.securityAdmin` | Service account IAM binding management |
| `roles/editor` | General resource creation (VPC, firewall, NAT, static IPs) |
| `roles/dns.admin` | Cloud DNS record management (if using DNS features) |
| `roles/cloudfunctions.developer` | Cloud Functions (only if using DR failover automation) |

If `manage_terraform_service_account = true` is set, Terraform creates a dedicated service account and binds these roles automatically. Otherwise, ensure the executing identity already has them.

### Workload Identity (Pod-to-GCS Authentication)

LogScale pods authenticate to GCS using GKE Workload Identity -- no service account keys are needed. The module configures this automatically:

1. A GCP service account is bound to the Kubernetes service account via `iam.gke.io/gcp-service-account` annotation.
2. The GCP service account gets `roles/storage.objectUser` on the LogScale data bucket and access logs bucket.
3. LogScale is configured with `GCP_STORAGE_WORKLOAD_IDENTITY=true`.

**If your organization policy blocks service account key creation**, you must use Workload Identity with a pre-existing GCP service account:

```hcl
use_existing_gcp_sa  = true
existing_gcp_sa_name = "logscale-sa"
```

When `use_existing_gcp_sa = true` (the default), Terraform looks up the named GCP service account via data source instead of creating one. The service account must already exist with the following IAM roles on the project:

| Role | Purpose |
|---|---|
| `roles/container.admin` | GKE cluster lifecycle |
| `roles/compute.admin` | VPC, firewall, GLB, health checks |
| `roles/storage.admin` | GCS bucket creation + cross-bucket access for DR recovery |
| `roles/dns.admin` | Cloud DNS record management |
| `roles/iam.serviceAccountUser` | Workload Identity binding |
| `roles/cloudfunctions.developer` | Deploy failover Cloud Function (standby only) |
| `roles/pubsub.admin` | Failover alert topic/subscription (standby only) |
| `roles/monitoring.admin` | Failover alerting policy (standby only) |

---

## Deployment Mode 1: With Bastion

> **Note:** The bastion module is not included in the current DR branch. It previously existed as a standalone GCE module. The information below describes the bastion architecture for reference and for environments that include it.

### Architecture

The bastion creates a GCE compute instance inside the VPC with the following characteristics:

- **IAP SSH access** -- no public IP assigned to the bastion
- **tinyproxy** on port 8888 for HTTP/HTTPS proxying to the GKE API
- **Pre-installed tools**: kubectl, gcloud, terraform
- **Shielded VM** with vTPM enabled
- `block-project-ssh-keys = true` to prevent project-wide SSH key injection

### Configuration

```hcl
bastion_host_enabled = true       # default: true when bastion module present
bastion_machine_type = "e2-medium"
bastion_image_type   = "debian-cloud/debian-12"
```

### Access Pattern

SSH to the bastion through IAP with local port forwarding, then proxy kubectl through it:

```bash
# Step 1: Open an IAP SSH tunnel with port forwarding
gcloud compute ssh <bastion-name> \
  --project=<project-id> \
  --zone=<zone> \
  --tunnel-through-iap \
  --ssh-flag="-4 -L8888:localhost:8888 -N -q -f"

# Step 2: Access GKE through the proxy
HTTPS_PROXY=localhost:8888 kubectl get nodes
```

### Security Properties

- IAP restricts SSH to authenticated, authorized users only.
- No public IP is assigned to the bastion instance.
- The GKE API server is only reachable from the VPC, which the bastion sits in.
- `block-project-ssh-keys = true` prevents org-wide SSH keys from granting access.

---

## Deployment Mode 2: Without Bastion (Authorized Networks)

This is the standard deployment mode. The GKE cluster uses a public API endpoint with an optional authorized network allowlist.

> **Reference:** [Customize your network isolation in GKE](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation)
>
> Google recommends combining **authorized networks** (IP-based access control) with a **DNS-based endpoint** for control plane access. The DNS-based endpoint uses IAM for authentication rather than network-level CIDR restrictions, and supports VPC Service Controls for an additional security boundary. This module implements the IP-based approach with `master_authorized_networks_config`. DNS-based endpoints are not configured by this module but can be enabled independently at the cluster level via Console or gcloud.

### Configuration

```hcl
private_nodes = "true"

# Optional: restrict which IPs can reach the Kubernetes API server.
# If omitted or empty, only GCP's own public CIDRs (Cloud Shell, etc.) can reach the API.
# Add "0.0.0.0/0" to allow unrestricted access.
ip_ranges_allowed_to_kubeapi = [
  "198.51.100.0/24",   # example: your office or VPN egress CIDR
]

# When true, the API endpoint is fully private (internal VPC only).
# Requires a bastion or VPN for access.
kubernetes_private_cluster_enabled = false
```

**Behavior by configuration:**

| `ip_ranges_allowed_to_kubeapi` | `kubernetes_private_cluster_enabled` | Result |
|---|---|---|
| `[]` (default) | `false` | API reachable from GCP public CIDRs only (Cloud Shell, GCE instances) |
| `["198.51.100.0/24"]` | `false` | API reachable from listed CIDRs + GCP public CIDRs |
| `["0.0.0.0/0"]` | `false` | API reachable from anywhere (not recommended for production) |
| any | `true` | API only reachable from internal VPC IPs (bastion/VPN required) |

### Access Pattern

```bash
# Authenticate
gcloud auth login
gcloud config set project <project-id>

# Get cluster credentials
gcloud container clusters get-credentials <cluster-name> \
  --region <region> --project <project-id>

# Access from an authorized network
kubectl get nodes
```

### Security Properties

- Only IPs in `ip_ranges_allowed_to_kubeapi` can reach the Kubernetes API.
- Worker nodes have private IPs only (`private_nodes = "true"`).
- Egress traffic goes through Cloud NAT (no public IPs on nodes).

---

## Terraform Configuration

### Backend Configuration

The module uses GCS for Terraform state storage. Create a GCS bucket first, then configure the backend:

```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "your-tf-state-bucket"
    prefix = "logscale/gcp/terraform/tf.state"
  }
}
```

Create the state bucket before running `terraform init`:

```bash
gsutil mb -p <project-id> -l <region> gs://your-tf-state-bucket
gsutil versioning set on gs://your-tf-state-bucket
```

### Variable File

Create `terraform.tfvars` (a complete example is provided in `terraform.tfvars.example`):

```hcl
# --- Required ---

project_id            = "your-gcp-project"
region                = "us-central1"
zone                  = "us-central1-a"
public_url            = "logscale.yourdomain.com"
logscale_cluster_type = "basic"   # basic | ingress | dedicated-ui | advanced
logscale_cluster_size = "xsmall"  # xsmall | small | medium | large | xlarge

# --- Versions ---

humio_operator_chart_version   = "0.29.2"
humio_operator_version         = "0.29.2"
logscale_image_version         = "1.228.1"
strimzi_operator_version       = "0.44.0"
strimzi_operator_chart_version = "0.44.0"

# --- Certificate Manager ---

cm_namespace       = "cert-manager"
cm_repo            = "https://charts.jetstack.io"
cm_version         = "v1.17.2"
issuer_kind        = "ClusterIssuer"
issuer_name        = "letsencrypt-cluster-issuer"
issuer_email       = "admin@yourdomain.com"
issuer_private_key = "letsencrypt-cluster-issuer-key"
ca_server          = "https://acme-v02.api.letsencrypt.org/directory"

# --- Network ---

gcp_cidr_range               = "10.128.0.0/20"
cluster_ipv4_cidr_block      = "10.0.0.0/14"
services_ipv4_cidr_block     = "172.16.1.0/24"
master_ipv4_cidr_block       = "172.16.0.0/28"
ip_ranges_allowed_to_kubeapi = ["203.0.113.0/24"]

# --- Storage ---

gcs_bucket_name            = "myproject-logscale-storage"
logscale_access_logs_bucket = "myproject-logscale-access-logs"

# --- Service Account (Workload Identity) ---
# Optional. If omitted, Terraform creates a new GCP service account automatically.
# Set these to reference a pre-existing SA (e.g., when org policy blocks SA creation).

use_existing_gcp_sa  = true
existing_gcp_sa_name = "logscale-sa"

# --- Kafka ---

provision_kafka_servers = true

# --- LogScale License ---

humiocluster_license = "your-license-jwt-token"
```

### Key Variables Reference

| Variable | Default | Description |
|---|---|---|
| `project_id` | (required) | GCP project ID |
| `region` | `us-central1` | GCP region for all resources |
| `zone` | `us-central1-a` | GCP zone (used by some zonal resources) |
| `public_url` | (required) | Public FQDN for LogScale UI |
| `logscale_cluster_type` | (required) | Cluster topology: `basic`, `ingress`, `dedicated-ui`, `advanced` |
| `logscale_cluster_size` | `xsmall` | Cluster size preset |
| `infrastructure_prefix` | `logscale` | Prefix for all resource names |
| `resource_name_prefix` | `logscale` | Prefix for Kubernetes resource names (max 8 chars) |
| `private_nodes` | `true` | GKE nodes get private IPs only |
| `kubernetes_private_cluster_enabled` | `false` | Fully private API endpoint (no public access) |
| `min_master_version` | `1.33.5-gke.1791000` | GKE control plane version |
| `node_pool_version` | `1.33.5-gke.1791000` | GKE node pool version |
| `use_kubeconfig_auth` | `true` | Use kubeconfig file for provider auth |
| `deletion_protection` | `true` | Prevent accidental cluster deletion |
| `use_own_certificate_for_ingress` | `true` | Use GCP-managed certs (set `false` for cert-manager) |
| `enable_shielded_nodes` | `true` | Enable GKE Shielded Nodes |

---

## Deployment Steps

### Step-by-Step Targeted Deployment (Recommended)

Deploying in stages with `-target` flags provides better error isolation and faster iteration:

```bash
# 1. Initialize Terraform
terraform init

# 2. Deploy VPC, static IPs, NAT, and firewall rules
terraform apply -target=module.vpc

# 3. Deploy GKE cluster and node pools
terraform apply -target=module.gke

# 4. Get kubeconfig for the new cluster
gcloud container clusters get-credentials \
  $(terraform output -raw cluster_name) \
  --region $(terraform output -raw logscale_cluster_region) \
  --project $(terraform output -raw logscale_cluster_project_id)

# 5. Deploy CRDs (cert-manager, Strimzi operator, Humio operator)
terraform apply -target=module.logscale.module.crds

# 6. Deploy post-install resources (encryption keys, ingress, NodePort service)
terraform apply -target=module.kubernetes_post_install

# 7. Deploy LogScale (HumioCluster CR, Kafka cluster, operators)
terraform apply -target=module.logscale

# 8. Bind Workload Identity for all LogScale service accounts
terraform apply -target=google_service_account_iam_member.logscale_nodepool_wl_binding

# 9. Full apply to catch any remaining resources
terraform apply

# 10. Verify deployment
kubectl get nodes
kubectl get pods -n log
kubectl get humiocluster -n log
```

### Single-Command Deployment

If you prefer a single apply (takes longer, harder to debug failures):

```bash
terraform init
terraform apply
```

Note: The first `terraform apply` may fail on CRD-dependent resources because CRDs are installed mid-apply. If this happens, run `terraform apply` a second time.

---

## Getting Access to the Cluster

After deployment, Terraform outputs the exact gcloud command needed:

```bash
# Print the credential command
terraform output k8s_configuration_command
```

This outputs something like:

```bash
gcloud container clusters get-credentials logscale-gke \
  --region us-central1 --project your-gcp-project
```

### Method 1: Direct Access (Authorized Networks)

```bash
gcloud auth login
eval "$(terraform output -raw k8s_configuration_command)"
kubectl get nodes
```

### Method 2: Bastion SSH Tunnel (If Bastion Enabled)

```bash
# Open IAP tunnel
gcloud compute ssh <bastion-name> \
  --project=<project-id> \
  --zone=<zone> \
  --tunnel-through-iap \
  --ssh-flag="-4 -L8888:localhost:8888 -N -q -f"

# Use the proxy
HTTPS_PROXY=localhost:8888 kubectl get nodes
```

### Verify

```bash
kubectl get nodes
kubectl get pods -n log
kubectl get humiocluster -n log -o yaml
```

---

## Port Forwarding for LogScale UI

To access the LogScale UI locally before DNS is configured:

```bash
# Forward LogScale HTTP service to localhost
kubectl port-forward svc/$(terraform output -raw cluster_name)-logscale-http \
  -n log 8080:8080

# Open in browser: http://localhost:8080
```

---

## Cluster Types

The `logscale_cluster_type` variable controls which node pools are created and how traffic is routed:

| Type | Node Pools Created | Best For |
|---|---|---|
| `basic` | Digest + Kafka | Development, small test clusters |
| `ingress` | Digest + Kafka (with ingress) | Small clusters with external access |
| `dedicated-ui` | Digest + UI + Kafka | Production with a separate UI tier |
| `advanced` | Digest + UI + Ingest + Kafka | Full production with dedicated ingest |

- **basic** and **ingress**: All LogScale pods run on the digest node pool. Simplest to operate.
- **dedicated-ui**: UI pods run on dedicated `e2-highmem-8` nodes, isolating search queries from ingest.
- **advanced**: Adds a dedicated ingest pool. Digest, UI, and ingest pods each get their own nodes. Recommended for high-volume production.

---

## Cluster Sizes

The `logscale_cluster_size` variable selects a predefined sizing template. All sizes use local SSDs on digest nodes (via TopoLVM) and SSD persistent disks (`pd-ssd`) for root and Kafka storage.

| Size | Digest Nodes | Digest Machine | Ingest Nodes | UI Nodes | Kafka Brokers | Kafka Machine |
|---|---|---|---|---|---|---|
| `xsmall` | 3 | n2-highmem-16 | 3 | 3 | 3 | n2-standard-16 |
| `small` | 9 | n2-highmem-16 | 3 | 3 | 6 | n2-highmem-8 |
| `medium` | 21 | n2-highmem-32 | 6 | 6 | 9 | n2-highmem-16 |
| `large` | 42 | n2-highmem-32 | 9 | 9 | 9 | n2-highmem-16 |
| `xlarge` | 78 | n2-highmem-64 | 9 | 9 | 18 | n2-highmem-32 |

Note: Ingest and UI node pools are only created for `dedicated-ui` and `advanced` cluster types. For `basic` and `ingress` types, those pods run on digest nodes.

---

## Scaling

### Vertical Scaling (Change Cluster Size)

To scale from one size to another:

1. Update `logscale_cluster_size` in `terraform.tfvars` (e.g., `xsmall` to `small`).
2. Run `terraform apply`.
3. GKE autoscaler provisions new nodes with the updated machine types and counts.
4. The LogScale operator reschedules pods across the new node topology.

### Topology Change (Change Cluster Type)

To add dedicated node pools:

1. Update `logscale_cluster_type` (e.g., `basic` to `advanced`).
2. Run `terraform apply`.
3. New node pools (UI, Ingest) are created.
4. The LogScale operator deploys pods to the new pools using node affinity.

### Manual Node Count Override

For fine-grained control, you can override the autoscaler bounds from the template by modifying the node pool min/max counts in the GKE module. However, the recommended approach is to select the appropriate `logscale_cluster_size` preset.

---

## General Troubleshooting

### `terraform apply` fails with "permission denied"

Verify the executing identity has the required IAM roles listed in the [Authentication](#authentication) section:

```bash
gcloud projects get-iam-policy <project-id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:<sa-email>"
```

### GKE cluster creation times out

Check GKE quota in the project. Common limits:

```bash
gcloud compute project-info describe --project=<project-id> \
  | grep -A2 "CPUS\|SSD_TOTAL_GB\|IN_USE_ADDRESSES"
```

Request quota increases for `CPUS`, `SSD_TOTAL_GB`, and `N2_CPUS` in the target region.

### LogScale pods in CrashLoopBackOff

1. **Check license secret**: Verify the `humiocluster_license` value is a valid JWT token.
   ```bash
   kubectl get secret -n log | grep license
   kubectl logs -n log -l app.kubernetes.io/name=humio --tail=50
   ```

2. **Check GCS authentication**: Verify Workload Identity is configured correctly.
   ```bash
   kubectl describe sa -n log | grep "iam.gke.io/gcp-service-account"
   ```

3. **Check encryption key secret**: The encryption key Kubernetes secret must exist.
   ```bash
   kubectl get secret -n log | grep encryption
   ```

### GCS access denied from LogScale pods

Verify the Workload Identity chain:

```bash
# Check K8s service account annotation
kubectl get sa -n log -o yaml | grep "iam.gke.io/gcp-service-account"

# Check GCP SA has storage permissions
gcloud storage buckets get-iam-policy gs://<bucket-name> \
  --format="table(bindings.role, bindings.members)"

# Check workload identity binding
gcloud iam service-accounts get-iam-policy <gcp-sa-email> \
  --format="table(bindings.role, bindings.members)" \
  | grep workloadIdentityUser
```

### CRD installation fails

CRDs (cert-manager, Strimzi, Humio operator) must be installed before resources that depend on them. Run the CRD target separately:

```bash
terraform apply -target=module.logscale.module.crds
terraform apply
```

### Terraform provider auth fails with "transport is closing"

This usually means the kubeconfig is stale or the cluster is unreachable. Regenerate credentials:

```bash
gcloud container clusters get-credentials <cluster-name> \
  --region <region> --project <project-id>
```

If using `use_kubeconfig_auth = false` (in-line auth), ensure `gcloud auth application-default login` has been run recently -- the token expires after one hour.

---

## Monitoring

After deployment, the monitoring stack (Prometheus, Grafana, Alertmanager) is deployed to the `monitoring` namespace. Access via port forwarding:

```bash
# Prometheus
kubectl port-forward svc/prometheus-server -n monitoring 9090:9090
# Open: http://localhost:9090

# Grafana
kubectl port-forward svc/grafana -n monitoring 3000:3000
# Open: http://localhost:3000

# Alertmanager
kubectl port-forward svc/alertmanager -n monitoring 9093:9093
# Open: http://localhost:9093
```

---

## Module Architecture

The `logscale-gcp` module is composed of the following submodules:

```
logscale-gcp/
  modules/
    gcp/
      bastion/                IAP-tunneled bastion host (optional)
      cloud-armor/            Cloud Armor WAF policies (optional)
      vpc/                    VPC, subnets, NAT, static IPs, firewall rules
      gke/                    GKE cluster, node pools, storage buckets, workload identity
      dns-failover/           Cloud DNS health-checked routing (DR)
      dr-failover-function/   Cloud Function for automated DR failover (DR)
      global-lb/              Global External Application Load Balancer (DR)
    kubernetes/
      post-install/           Encryption keys, ingress, NodePort service, GCP-specific K8s resources
  main.tf                     Orchestrates all modules
  cluster_size.tpl            Node pool sizing presets (xsmall through xlarge)
```

The `logscale-kubernetes` module (sourced from `github.com/CrowdStrike/logscale-kubernetes`) is a shared module that handles CRD installation, Helm chart deployments, HumioCluster CR creation, and Kafka/Strimzi setup. It is cloud-agnostic.

---
