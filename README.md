![CrowdStrike Falcon](https://raw.githubusercontent.com/CrowdStrike/falconpy/main/docs/asset/cs-logo.png) [![Twitter URL](https://img.shields.io/twitter/url?label=Follow%20%40CrowdStrike&style=social&url=https%3A%2F%2Ftwitter.com%2FCrowdStrike)](https://twitter.com/CrowdStrike)<br/>

# LogScale Reference Automations for GCP

Terraform configurations to deploy CrowdStrike LogScale on Google Kubernetes Engine (GKE). Supports single-cluster and active-standby disaster recovery topologies.

LogScale GCP is an open source project and not a CrowdStrike product. As such, it carries no formal support, expressed, or implied.

## Prerequisites

- Terraform >= 1.5
- kubectl >= 1.27
- GKE Kubernetes >= 1.34
- gcloud CLI (authenticated)
- Helm v3
- GCP project with billing enabled
- Service account with IAM roles: `roles/editor`, `roles/container.admin`, `roles/iam.securityAdmin`, `roles/storage.objectAdmin`

```bash
# Set Application Default Credentials (Terraform picks these up automatically)
gcloud auth application-default login

# Or impersonate a service account (no key file needed):
# gcloud auth application-default login --impersonate-service-account=SA@PROJECT.iam.gserviceaccount.com
```

## Quick Start

```bash
git clone <this-repo>
cd logscale-gcp

cp example.tfvars terraform.tfvars
# Edit terraform.tfvars with your values
```

### Setup

1. Create a GCS bucket for Terraform state and set the name in `backend.tf`:

```bash
gsutil mb gs://your-terraform-state-bucket
```

2. Export the LogScale license:

```bash
export TF_VAR_humiocluster_license=<your_logscale_license>
```

### Deploy

Deployment uses targeted applies to respect module dependencies. When running a
full `terraform apply` (without targets), the dependency graph ensures correct
ordering — `module.logscale` depends on `module.kubernetes_post_install` which
creates the LogScale namespace and GCP-specific Kubernetes resources:

```bash
terraform init

# 1. Network infrastructure
terraform apply -target="module.vpc"

# 2. GKE cluster and node pools
terraform apply -target="module.gke"

# 3. (Optional) Bastion host for private clusters
# terraform apply -target="module.bastion"
# When using a bastion, subsequent kubectl/terraform commands that reach
# the Kubernetes API must run through the bastion's tinyproxy tunnel.

# 4. Get kubeconfig
gcloud container clusters get-credentials <cluster-name> --region <region> --project <project-id>

# 5. Kubernetes pre-install (namespace)
terraform apply -target="module.kubernetes_pre_install"

# 6. LogScale CRDs
terraform apply -target="module.logscale.module.crds"

# 7. LogScale prereqs (cert-manager + secrets)
terraform apply -target="module.logscale.module.logscale-prereqs"

# 8. Kubernetes post-install (GCP encryption keys, ingress, NodePort)
terraform apply -target="module.kubernetes_post_install"

# 9. LogScale (Strimzi, Humio operator, HumioCluster CR)
terraform apply -target="module.logscale"

# 10. Workload Identity binding (must be separate — depends on both GKE and LogScale)
terraform apply -target="google_service_account_iam_member.logscale_nodepool_wl_binding"
```

For DR deployments, additional targeted applies are required after step 10.
See [docs/dr-readme.md](docs/dr-readme.md) for the full DR deployment sequence.

When using external ingress (`ingress_mode = "external-restricted"` or `enable_global_lb = true`), create a DNS A record pointing `public_url` to the reserved static IP:

```bash
terraform output -raw gce_ingress_ip_address
```

## Required Variables

```hcl
project_id             = "your-gcp-project-id"
region                 = "us-central1"
zone                   = "us-central1-a"
public_url             = "logscale.your-domain.com"
gcs_bucket_name        = "your-unique-logscale-storage"
logscale_cluster_type  = "basic"  # basic | dedicated-ui | advanced
logscale_cluster_size  = "xsmall" # xsmall | small | medium | large | xlarge
```

Component versions (Humio operator, LogScale image, Strimzi) must be set in `terraform.tfvars`. See [example.tfvars](example.tfvars) for current minimum versions.

For the complete variable reference, see [docs/variables-inventory.md](docs/variables-inventory.md).

## Modules

### VPC (`modules/gcp/vpc`)

Provisions networking: VPC, subnets, firewall rules, Cloud NAT, static IPs. Creates a proxy subnetwork for internal load balancing when `logscale_cluster_type = "advanced"`.

### GKE (`modules/gcp/gke`)

Provisions the GKE cluster, node pools, GCS storage buckets, service accounts, and Workload Identity bindings. Node pool topology is determined by `logscale_cluster_type`:

| Type | Node Pools |
|------|-----------|
| `basic` | Digest + Kafka |
| `dedicated-ui` | Digest + UI + Kafka |
| `advanced` | Digest + UI + Ingest + Kafka |

Kafka pool is omitted when `provision_kafka_servers = false`.

### Kafka

LogScale requires Apache Kafka for partition management. This module deploys Strimzi (in-cluster Kafka operator) by default. There is no Google Cloud Managed Kafka integration at this time.

| Mode | Setting | Description |
|------|---------|-------------|
| Strimzi (default) | `provision_kafka_servers = true` | Deploys Strimzi operator + Kafka brokers on dedicated node pool |
| Bring Your Own | `provision_kafka_servers = false` | Skips Strimzi. Requires external Kafka and setting `byo_kafka_connection_string` in the `logscale-kubernetes` module |

The BYO path is supported by `logscale-kubernetes` but is not fully wired through this GCP wrapper — manual passthrough required if using external Kafka.

### Kubernetes Pre-Install (`modules/kubernetes/pre-install`)

Creates the LogScale namespace. Runs before post-install and logscale-kubernetes to guarantee the namespace exists for all subsequent Kubernetes resources. Aligns with the AWS, Azure, and OCI pre-install pattern.

### Kubernetes Post-Install (`modules/kubernetes/post-install`)

Deploys GCP-specific Kubernetes resources: Google Managed Certificates, BackendConfig for health checks, NodePort services, GKE Ingress, GCS encryption secrets, and DR recovery secrets when applicable.

### Bastion (`modules/gcp/bastion`)

Optional bastion host for private GKE clusters. Provides IAP-tunneled SSH access and a tinyproxy instance for routing kubectl and Terraform traffic to the cluster API. Enable with `provision_bastion = true`.

### LogScale ([logscale-kubernetes](https://github.com/CrowdStrike/logscale-kubernetes))

Cloud-agnostic module that deploys Strimzi Kafka, the Humio operator, and the HumioCluster CR. Consumed by this GCP wrapper and by the AWS, Azure, and OCI equivalents.

### DR Failover Function (`modules/gcp/dr-failover-function`)

Optional Cloud Function for automated failover. Monitors primary health via Uptime Check or GLB backend health, triggers standby scale-up via Pub/Sub. Only created when `dr_cloud_function_enabled = true` on standby.

### DNS Failover (`modules/gcp/dns-failover`)

Weighted Round Robin DNS routing with health checks. Creates A records for primary/secondary and a global CNAME. Disabled when GLB is enabled.

### Global Load Balancer (`modules/gcp/global-lb`)

GCP External Application Load Balancer for health-based DR failover. Primary backend at full capacity, secondary at zero (failover-only). Created on primary when `enable_global_lb = true`.

## Storage Classes

LogScale GCP uses storage classes optimized for each component:

- **Digest pods**: `topolvm-provisioner` — local NVMe SSDs for high-throughput indexing
- **UI/Ingest pods**: `premium-rwo` — persistent SSD disks
- **Kafka brokers**: `premium-rwo` — reliable persistent storage

## Kubernetes API Access

The GKE control plane restricts API access by default. Configure access via:

```hcl
# Allow specific IPs
ip_ranges_allowed_to_kubeapi = ["198.51.100.10/32"]

# Or unrestricted (not recommended for production)
ip_ranges_allowed_to_kubeapi = ["0.0.0.0/0"]
```

When `ip_ranges_allowed_to_kubeapi` is empty (default), only GCP public CIDRs can reach the API. Set `kubernetes_private_cluster_enabled = true` to restrict to internal networks only.

## Private Cluster Access (Bastion)

When `kubernetes_private_cluster_enabled = true`, the GKE control plane has no public endpoint. All `kubectl` and `terraform` commands that target the Kubernetes API must route through the bastion host's tinyproxy via an IAP SSH tunnel.

### Prerequisites

- `bastion_host_enabled = true` (enforced — terraform plan fails without it)
- IAM: `roles/iap.tunnelResourceAccessor` on the bastion instance
- IAM: `roles/compute.osLogin` on the project (OS Login is enforced on the bastion)

### Deployment Scope

The CI/CD pipeline deploys infrastructure up to and including the bastion:
VPC → GKE → Bastion → **(stops here)**

It **cannot** deploy LogScale or any Kubernetes resources on private clusters because IAP tunnel connections require interactive SSH sessions not supported from within workflow pods. After the pipeline completes the infrastructure phase, continue manually.

### Manual Steps (after pipeline deploys infra)

```bash
# 1. Open IAP tunnel to bastion's tinyproxy (port 8888)
gcloud compute ssh <infrastructure_prefix>-bastion \
  --tunnel-through-iap \
  --project=<project_id> \
  --zone=<region>-a \
  -- -L 8888:localhost:8888 -N -f

# 2. Get kubeconfig (routed through proxy to private endpoint)
HTTPS_PROXY=localhost:8888 gcloud container clusters get-credentials \
  <cluster-name> --region <region> --project <project_id> --internal-ip

# 3. Verify connectivity
HTTPS_PROXY=localhost:8888 kubectl get nodes

# 4. Continue targeted applies through proxy
export HTTPS_PROXY=localhost:8888
terraform apply -target="module.kubernetes_pre_install"
terraform apply -target="module.logscale.module.crds"
terraform apply -target="module.logscale.module.logscale-prereqs"
terraform apply -target="module.kubernetes_post_install"
terraform apply -target="module.logscale"
terraform apply -target="google_service_account_iam_member.logscale_nodepool_wl_binding"
```

### Configuration

See the **BASTION HOST** section in [example.tfvars](example.tfvars) for all variables and defaults.

### Notes

- The bastion has no external IP — access is exclusively through IAP TCP forwarding
- tinyproxy binds to `127.0.0.1:8888` — only accessible via the SSH tunnel
- The bastion service account must pre-exist (GCP org policy blocks SA creation)
- When bastion is enabled, the VPC subnet CIDR is automatically added to the cluster's authorized networks

## Disaster Recovery

Active-standby (warm) DR across two GCP regions. The standby cluster runs with minimal pods and recovery configuration ready — not a hot standby. See [docs/dr-readme.md](docs/dr-readme.md) for architecture, deployment stages, failover, and promotion procedures.

Before deploying DR, a Cloud DNS managed zone must exist:

```bash
gcloud dns managed-zones create <zone-name> \
  --dns-name="<your-domain>." \
  --description="DR failover zone" \
  --project=<project-id>
```

### DR Documentation

| Document | Description |
|----------|-------------|
| [DR Guide](docs/dr-readme.md) | Architecture, deployment, failover, promotion |
| [DR Data Flow](docs/dr-data-flow.md) | Encryption key sync, GCS recovery, env vars |
| [DR Node Pool Topology](docs/dr-node-pool-topology.md) | Node pools by type, DR impact, promotion phases |
| [DR Post-Install Checklist](docs/dr-postinstall-checklist.md) | Verification steps for DR pairs |

## Getting Help

Create an issue on our [Github repo](https://github.com/CrowdStrike/logscale-gcp) for bugs, enhancements, or other requests.

## Contributing

- Raise issues you find using LogScale GCP
- Fix issues by opening [Pull Requests](https://github.com/CrowdStrike/logscale-gcp/pulls)
- Improve documentation

All bugs, tasks or enhancements are tracked as [GitHub issues](https://github.com/CrowdStrike/logscale-gcp/issues).

## References

- [LogScale Documentation](https://library.humio.com/)
- [LogScale Training](https://library.humio.com/training/training-fc.html)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [GCP Network Isolation](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/latest/network-isolation)
- [Humio Operator](https://github.com/humio/humio-operator)
- [LogScale Kubernetes Module](https://github.com/CrowdStrike/logscale-kubernetes)
- [Strimzi Documentation](https://strimzi.io/documentation/)
- [Cert Manager Documentation](https://cert-manager.io/docs/)
- [Deploying LogScale on GCP](https://library.humio.com/falcon-logscale-self-hosted-1.131/installation-containers-kubernetes-gcp-install.html)
