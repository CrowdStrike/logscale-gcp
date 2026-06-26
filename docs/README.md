# LogScale on GCP — Reference Architecture

Terraform-based deployment of CrowdStrike LogScale on Google Kubernetes Engine (GKE).

## Deployment Modes

### Single Cluster (default)

Standard deployment with one GKE cluster. Set `dr = "active"` (or omit — it's the default).

### Disaster Recovery (Active/Standby)

Cross-region DR with automated failover. Deploy a primary (`dr = "active"`) and a warm standby (`dr = "standby"`) in separate regions. The standby runs with minimal pods and recovery configuration ready — it is not a hot standby. On promotion, the standby recovers from the primary's GCS bucket.

See [dr-readme.md](dr-readme.md) for full DR documentation.

## Cluster Types

| Type | Node Pools | Use Case |
|------|-----------|----------|
| `basic` | Digest + Kafka | Dev/test, small workloads |
| `dedicated-ui` | Digest + UI + Kafka | Separate UI serving from query processing |
| `advanced` | Digest + UI + Ingest + Kafka | Full production topology with dedicated ingest |

Set via `logscale_cluster_type`. The Kafka pool is omitted when `provision_kafka_servers = false` (bring-your-own Kafka).

## Cluster Sizes

| Size | Digest Nodes | Machine Type | Estimated Daily Ingest |
|------|-------------|--------------|----------------------|
| `xsmall` | 3 | n2-highmem-16 | Up to 1 TB/day |
| `small` | 9 | n2-highmem-16 | 1–5 TB/day |
| `medium` | 21 | n2-highmem-32 | 5–20 TB/day |
| `large` | 42 | n2-highmem-32 | 20–50 TB/day |
| `xlarge` | 78 | n2-highmem-64 | 50+ TB/day |

Set via `logscale_cluster_size`. Full node pool specifications in [dr-node-pool-topology.md](dr-node-pool-topology.md).

## Network Access

| Setting | API Access |
|---------|-----------|
| `kubernetes_private_cluster_enabled = true` | Internal networks only |
| `kubernetes_private_cluster_enabled = false` + `ip_ranges_allowed_to_kubeapi = []` | GCP public CIDRs only |
| `kubernetes_private_cluster_enabled = false` + `ip_ranges_allowed_to_kubeapi = ["0.0.0.0/0"]` | Unrestricted |

See Google's [network isolation guide](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation) for recommended configurations.

## Quick Start

```hcl
module "logscale" {
  source = "."

  project_id             = "my-project"
  region                 = "us-central1"
  zone                   = "us-central1-a"
  logscale_cluster_type  = "basic"
  logscale_cluster_size  = "xsmall"
  public_url             = "logscale.example.com"

  # Versions
  humio_operator_chart_version = "0.31.1"
  humio_operator_version       = "0.31.1"
  logscale_image_version       = "1.228.3"
  strimzi_operator_version     = "0.45.0"
}
```

## Documentation Index

| Document | Description |
|----------|-------------|
| [variables-inventory.md](variables-inventory.md) | Complete variable reference |
| [dr-readme.md](dr-readme.md) | DR architecture, prerequisites, deployment stages |
| [dr-data-flow.md](dr-data-flow.md) | DR data flow, env vars, recovery mechanics |
| [dr-node-pool-topology.md](dr-node-pool-topology.md) | Node pool layout by cluster type and size |
| [dr-postinstall-checklist.md](dr-postinstall-checklist.md) | Post-deploy verification for DR pairs |
| [dr-changelog.md](dr-changelog.md) | DR feature changelog |

## Prerequisites

- GCP project with billing enabled
- Terraform >= 1.5
- `gcloud` CLI authenticated
- Service account with required IAM roles (see [variables-inventory.md](variables-inventory.md#service-account))
- DNS zone (if using managed certificates or DR failover)
