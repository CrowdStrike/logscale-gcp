# GKE Node Pool Topology -- Cluster Types and DR Impact

This document describes how GKE node pools are created based on `logscale_cluster_type`, how DR mode affects the HumioCluster CR (but not node pool topology), and the two-phase promotion workflow for zero-downtime failover.

---

## Node Pools by Cluster Type

| Cluster Type   | Digest NP     | UI NP                          | Ingest NP          | Kafka NP                            | Use Case                          |
|----------------|---------------|--------------------------------|--------------------|-------------------------------------|-----------------------------------|
| `basic`        | Yes (always)  | No                             | No                 | Yes (if `provision_kafka_servers`)   | Dev/test, small deployments       |
| `dedicated-ui` | Yes (always)  | Yes                            | No                 | Yes (if `provision_kafka_servers`)   | Separate UI serving               |
| `advanced`     | Yes (always)  | Yes                            | Yes                | Yes (if `provision_kafka_servers`)   | Full production topology          |

**Source**: Node pool creation is controlled entirely by `logscale_cluster_type` in the GKE module:

- Digest: `modules/gcp/gke/logscale-node-pool.tf` -- always created, no count guard
- UI: `modules/gcp/gke/ui-node-pool.tf` -- `count = contains(["dedicated-ui", "advanced"], var.logscale_cluster_type) ? 1 : 0`
- Ingest: `modules/gcp/gke/advanced-node-pool.tf` -- `count = contains(["advanced"], var.logscale_cluster_type) ? 1 : 0`
- Kafka: `modules/gcp/gke/kafka-node-pool.tf` -- `count = var.provision_kafka_servers == true ? 1 : 0`

---

## Node Pool Details

### Digest Node Pool (always created)

- **Resource**: `google_container_node_pool.logscale_node_pool`
- **Name pattern**: `{cluster_name}-np-logscale` or `{infrastructure_prefix}-np-logscale`
- **Labels**: `k8s-app=logscale-digest`, `storageclass=nvme`
- **Initial nodes per zone**: `ceil(logscale_digest_node_count / 3)`
- **Autoscaling**: min/max from `cluster_size.tpl` lookup
- **Storage**: Local NVMe SSDs (count from `logscale_digest_local_ssd_count`)
- **Purpose**: Core LogScale processing -- queries, indexing, segment management

### UI Node Pool (dedicated-ui or advanced)

- **Resource**: `google_container_node_pool.logscale_ui_node_pool`
- **Name pattern**: `{cluster_name}-np-ui` or `{infrastructure_prefix}-np-ui`
- **Labels**: `k8s-app=logscale-ui`
- **Initial nodes per zone**: `ceil(logscale_ui_node_count / 3)`
- **Storage**: PD-SSD root disk only (no local NVMe)
- **Purpose**: Web UI serving, query frontend, dashboard rendering

### Ingest Node Pool (advanced only)

- **Resource**: `google_container_node_pool.logscale_ingest_node_pool`
- **Name pattern**: `{cluster_name}-np-ingest` or `{infrastructure_prefix}-np-ingest`
- **Labels**: `k8s-app=logscale-ingest`
- **Initial nodes per zone**: `ceil(logscale_ingest_node_count / 3)`
- **Storage**: PD-SSD root disk only (no local NVMe)
- **Purpose**: High-volume data ingestion, parser execution

### Kafka Node Pool (when provision_kafka_servers=true)

- **Resource**: `google_container_node_pool.kafka_node_pool`
- **Name pattern**: `{cluster_name}-np-kafka` or `{infrastructure_prefix}-np-kafka`
- **Labels**: `k8s-app=strimzi`
- **Initial nodes per zone**: `ceil(kafka_broker_node_count / 3)`
- **Storage**: PD-SSD root disk, persistent disk for Kafka data (`kafka_broker_data_disk_size`)
- **Purpose**: Strimzi Kafka broker nodes

### Common Node Pool Properties

All node pools share these settings:

- `preemptible = false` (production workloads)
- `image_type = COS_CONTAINERD`
- `auto_repair = true`, `auto_upgrade = false`
- `create_before_destroy = true` lifecycle rule
- `delete timeout = 1h`
- `block-project-ssh-keys = true` metadata
- Workload Identity enabled on digest pool (`GKE_METADATA` mode)

---

## Cluster Size Definitions

Sizes are defined in `cluster_size.tpl` at the repo root. The values below are **node counts**, not GKE VM counts. GKE distributes nodes across 3 AZs, so `initial_node_count = ceil(count / 3)` per zone.

| Size    | Digest Nodes | Digest Machine      | UI Nodes | UI Machine       | Ingest Nodes | Ingest Machine   | Kafka Brokers | Kafka Machine    |
|---------|--------------|---------------------|----------|------------------|--------------|------------------|---------------|------------------|
| xsmall  | 3            | n2-highmem-16       | 3        | e2-highmem-8     | 3            | e2-highmem-8     | 3             | n2-standard-16   |
| small   | 9            | n2-highmem-16       | 3        | e2-highmem-8     | 3            | n2-standard-16   | 6             | n2-highmem-8     |
| medium  | 21           | n2-highmem-32       | 6        | n2-highmem-8     | 6            | n2-standard-8    | 9             | n2-highmem-16    |
| large   | 42           | n2-highmem-32       | 9        | n2-highmem-16    | 9            | n2-standard-16   | 9             | n2-highmem-16    |
| xlarge  | 78           | n2-highmem-64       | 9        | n2-highmem-32    | 9            | n2-standard-16   | 18            | n2-highmem-32    |

**Note**: All sizes define counts for all pool types (digest, UI, ingest, kafka), but UI and ingest pools are only created when `logscale_cluster_type` enables them. The size definitions exist in the template regardless.

---

## DR Impact on Node Pools

### Key Insight

GKE node pools are the SAME regardless of DR mode. The `dr` variable does NOT control which node pools are created. Only `logscale_cluster_type` and `provision_kafka_servers` determine node pool topology.

**What DR actually changes:**

1. The HumioCluster CR pod selectors (via `logscale-kubernetes` module)
2. LogScale environment variables (ENABLE_ALERTS, RECOVER_FROM_* vars)
3. Whether the humio-operator is scaled to 0 replicas (standby)
4. Whether DR-specific modules are created (Cloud Function, GLB, DNS failover)

### HumioCluster CR Behavior by DR State

| Setting                    | Active                                    | Standby (dr_use_dedicated_routing=true)   | Standby (dr_use_dedicated_routing=false) |
|----------------------------|-------------------------------------------|-------------------------------------------|------------------------------------------|
| Pod selector               | Dedicated per pool (digest, UI, ingest)   | Dedicated per pool                        | Generic: `app.kubernetes.io/name=humio`  |
| ENABLE_ALERTS              | `"true"`                                  | `"false"`                                 | `"false"`                                |
| GCP_RECOVER_FROM_BUCKET    | Not set                                   | Set (primary's GCS bucket)                | Set (primary's GCS bucket)               |
| GCP_RECOVER_FROM_*         | Not set                                   | Set (encryption key, replace region/bucket)| Set (encryption key, replace region/bucket)|
| GCP_STORAGE_BUCKET         | Own bucket                                | Own bucket                                | Own bucket                               |

### DR-Specific Environment Variables (Standby Only)

These environment variables are injected into the HumioCluster CR only when `dr = "standby"` (set in `main.tf` via `user_logscale_envvars`):

| Variable                              | Source                                          | Purpose                                              |
|---------------------------------------|------------------------------------------------|------------------------------------------------------|
| `GCP_RECOVER_FROM_BUCKET`             | Remote state or `gcp_recover_from_bucket` tfvar | Primary cluster's GCS bucket for snapshot recovery   |
| `GCP_RECOVER_FROM_WORKLOAD_IDENTITY`  | Hardcoded `"true"`                              | Use Workload Identity for cross-bucket access        |
| `GCP_RECOVER_FROM_REPLACE_REGION`     | Auto-generated or `gcp_recover_from_replace_region` | Path translation for region-prefixed object keys |
| `GCP_RECOVER_FROM_REPLACE_BUCKET`     | Auto-generated or `gcp_recover_from_replace_bucket` | Bucket name translation in stored references     |
| `GCP_RECOVER_FROM_ENCRYPTION_KEY`     | Secret ref from `kubernetes_post_install`       | Primary's GCS encryption key for reading snapshots   |

**Note**: `GCP_RECOVER_FROM_REGION` is NOT used by LogScale for GCS buckets. GCS does not need a region for bucket access (buckets are globally addressable). The `REPLACE_REGION` variable serves a different purpose: path translation in stored snapshot references.

---

## Promotion Workflow (Standby to Active)

Two-phase approach for zero-downtime failover. Controlled by `dr` and `dr_use_dedicated_routing` variables.

### Phase 1: Set `dr="active"` AND `dr_use_dedicated_routing=false`

```hcl
dr                       = "active"
dr_use_dedicated_routing = false
```

What happens:

- LogScale starts with generic pod selector: `{ "app.kubernetes.io/name" = "humio" }`
- All traffic goes to the digest pod (single pod type handles everything)
- ENABLE_ALERTS switches from `"false"` to `"true"`
- RECOVER_FROM_* environment variables are removed
- UI/Ingest node pools begin scaling up (if cluster_type requires them)
- Zero downtime because existing digest pod serves all requests while other pods start

### Phase 2: Set `dr_use_dedicated_routing=true`

```hcl
dr                       = "active"
dr_use_dedicated_routing = true   # or simply remove the override (true is default)
```

What happens:

- Pod selectors switch to dedicated per-pool routing
- Traffic routes to correct pools: UI pods serve web traffic, Ingest pods handle data, Digest pods process queries
- Full production topology restored with optimized resource utilization

### Why Two Phases?

If you set both `dr="active"` and `dr_use_dedicated_routing=true` in a single apply on a standby cluster, the service selectors immediately switch to pool-specific selectors (e.g., looking for `k8s-app=logscale-ui` pods). If those pods have not started yet -- because the node pool was just scaled up or the operator is still deploying them -- there is a traffic blackhole. The two-phase approach avoids this by keeping the catch-all selector active until all pool types have running pods.

---

## Standby Components

### Running on Standby

| Component          | Reason                                                             |
|--------------------|--------------------------------------------------------------------|
| Kafka brokers      | Required for LogScale partition management and snapshot replication |
| GKE Ingress        | Maintains GLB health check via kube-proxy NodePort                 |
| cert-manager       | Certificate lifecycle management must continue                     |
| TopoLVM            | Storage provisioner must be ready for failover scale-up            |
| Node pools         | GKE nodes remain running (min autoscaling count)                   |

### Not Running on Standby (Until Failover)

| Component          | Reason                                                             |
|--------------------|--------------------------------------------------------------------|
| humio-operator     | Scaled to 0 replicas on standby                                   |
| LogScale pods      | Depend on operator; not deployed until promotion                   |
| UI/Ingest pods     | Node pools exist but LogScale pods are not scheduled               |

---

## DR Modules (Conditional)

These modules are created only for DR deployments and are gated by variables:

| Module                    | Condition                                                  | Created On     |
|---------------------------|------------------------------------------------------------|----------------|
| `dr_failover_function`    | `dr_cloud_function_enabled && dr == "standby"`             | Standby only   |
| `dns_failover`            | `!enable_global_lb && (manage_global_dns or DNS zones set)`| Primary or both|
| `global_lb`               | `enable_global_lb && dr == "active"`                       | Primary only   |

### Cloud Function (Standby)

Automated failover via:
1. GCP Uptime Check monitors primary's `/api/v1/status` endpoint
2. Alert policy triggers on consecutive failures (configurable via `pre_failover_failure_seconds`, default 180s)
3. Alert publishes to Pub/Sub topic
4. Cloud Function scales up standby cluster's operator and node pools

### Global Load Balancer (Primary)

Health-check-based failover using GCP's External Application Load Balancer:
- Primary backend: instance groups from primary GKE cluster
- Secondary backend: instance groups from secondary GKE cluster (via remote state)
- Health check on `/api/v1/status` (configurable path, port, type)
- Capacity scalers: primary=1.0 (full), secondary=0.0 (failover only)

### DNS Failover

WRR (Weighted Round Robin) DNS routing with health checks:
- Creates A records for primary and secondary hostnames
- Creates global CNAME pointing to healthy cluster
- TTL=30s for fast DNS failover
- Disabled when GLB is enabled (GLB handles DNS itself)
