![CrowdStrike Falcon](https://raw.githubusercontent.com/CrowdStrike/falconpy/main/docs/asset/cs-logo.png) [![Twitter URL](https://img.shields.io/twitter/url?label=Follow%20%40CrowdStrike&style=social&url=https%3A%2F%2Ftwitter.com%2FCrowdStrike)](https://twitter.com/CrowdStrike)<br/>

# LogScale Reference Automations for GCP

This repository contains Terraform configurations to deploy a comprehensive Google Cloud Platform (GCP)-based architecture for LogScale. It leverages multiple GCP services such as GKE, Cloud Storage, and Strimzi Kafka, as well as Kubernetes components like cert-manager and Helm to create a scalable, secure and robust LogScale deployment on GCP.

LogScale GCP is an open source project and not a CrowdStrike product. As such, it carries no formal support, expressed, or implied.

## Quick Start

### 1. Clone Required Repositories
```bash
# Clone both required repositories
git clone <this-repo>
git clone https://github.com/humio/logscale-kubernetes.git

# The directory structure should look like:
# parent-directory/
# ├── logscale-gcp-v2/
# └── logscale-kubernetes/

cd logscale-gcp-v2

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 2. Set Required Variables
Update `terraform.tfvars` with your specific values:
```hcl
# Required: Your GCP project and region
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Required: Globally unique bucket names
gcs_bucket_name             = "your-unique-logscale-storage"
logscale_access_logs_bucket = "your-unique-access-logs"

# Required: Your domain for LogScale UI
public_url = "logscale.your-domain.com"

# Required: Your LogScale license (get from CrowdStrike)
humiocluster_license = "your-jwt-token-here"
```

### 3. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Follow the detailed deployment steps below (sections 2.1-2.7)
# for the complete staged deployment process
```

### 4. Access LogScale
After deployment completes (5-10 minutes), access your LogScale instance at the `public_url` you configured.

Default credentials: `admin` / (check kubectl secret for password)

## Prerequisites

Before starting the deployment, ensure you have the following tools and access:

- **Terraform 1.1.0+**: Terraform is the infrastructure as code tool used to manage the deployment. Ensure you have version 1.1.0 or higher installed.
- **kubectl 1.27+**: kubectl is the command-line tool for interacting with the Kubernetes cluster. Make sure you have version 1.27 or above.
- **gcloud CLI**: The Google Cloud CLI allows you to interact with GCP services from the command line. Latest version is recommended.
- **Helm v3**: Helm is the package manager for Kubernetes, used to manage Kubernetes applications. Ensure you have version 3 or higher installed.
- **Access to a GCP project**: You need access to a GCP project with permissions to create and manage the necessary resources such as VPCs, GKE clusters, and Cloud Storage buckets.
- **Terraform Service Account**: You'll need to create a service account with the following IAM roles and export the GOOGLE_APPLICATION_CREDENTIALS environment variable:

  **Required IAM Roles:**
  - `Editor` - For general resource management (VPC, Storage, etc.)
  - `Kubernetes Engine Admin` - For GKE cluster and node pool management (automatically granted via `container.admin`)
  - `Security Admin` - For IAM policy bindings and workload identity configuration (automatically granted via `iam.securityAdmin`)
  - `Service Account Admin` - For service account creation and workload identity bindings (included in Editor role)

  **Note**: The Terraform code automatically creates a service account with these roles:
  - `roles/editor` - Provides broad project permissions including service account management
  - `roles/container.admin` - Equivalent to Kubernetes Engine Admin for GKE operations
  - `roles/iam.securityAdmin` - Required for service account IAM bindings
  - `roles/storage.objectAdmin` - For Cloud Storage bucket operations

  ```bash
  export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/service-account-key.json"
  ```

## Getting Access to GKE Cluster

After deployment, to access the GKE cluster with kubectl commands, you need to add your IP address to the authorized networks:

### 1. Get Your Current IP Address
```bash
# Get your public IP
curl ifconfig.me
```

### 2. Add IP to GKE Authorized Networks

**Option A: Via GCP Console (Recommended for first-time setup)**
1. Go to [GKE Clusters](https://console.cloud.google.com/kubernetes/list) in GCP Console
2. Click on your cluster name
3. Click **Edit** at the top
4. Under **Networking** → **Control plane authorized networks**
5. Click **Add authorized network**
6. Enter your IP with `/32` (e.g., `203.0.113.123/32`)
7. Add a description (e.g., "My laptop")
8. Click **Save**

**Option B: Via Code (For permanent access)**
1. Edit `terraform.tfvars` file
2. Add your IP to the `ip_ranges_allowed_to_kubeapi` list:
   ```hcl
   ip_ranges_allowed_to_kubeapi = [
     "YOUR.IP.ADDRESS/32",    # Add your IP here
     # Add other team members' IPs as needed
   ]
   ```
3. Apply the changes:
   ```bash
   terraform apply -target="module.gke"
   ```

### 3. Configure kubectl
```bash
# Authenticate with GCP
gcloud auth login

# Get cluster credentials (replace with your actual cluster name and project)
gcloud container clusters get-credentials <your-cluster-name> --zone <your-zone> --project <your-project-id>

# Test access
kubectl get namespaces
```

**Note**: If your IP address changes frequently (dynamic IP), you may need to update the authorized networks accordingly.

## Terraform Code Execution

### Setup steps

1.1 Ensure a GCS bucket is created to hold the terraform state, and add its name to `bucket` under the backend configuration section from `backend.tf`.

**Note:** The bucket name must be updated in **both** `backend.tf` and `variables.tf` (variable `logscale_gcp_tf_state_bucket`).

```bash
# Create GCS bucket for Terraform state
gsutil mb gs://your-terraform-state-bucket
```

1.2 Comment out the `providers.tf` file in the `../logscale-kubernetes` module to avoid provider conflicts during `terraform init`:

```bash
# Navigate to the logscale-kubernetes module and comment out providers.tf
cd ../logscale-kubernetes
mv providers.tf providers.tf.bak
# Or comment out the entire file content
```

1.3 Configure the following variables in the `terraform.tfvars` file:
- `project_id`: Your GCP project ID
- `region`: GCP region for deployment (e.g., `us-central1`)
- `zone`: GCP zone for deployment (e.g., `us-central1-a`)
- `public_url`: Public URL for the LogScale cluster
- `gcs_bucket_name`: Cloud Storage bucket name for LogScale data (must be globally unique)
- `logscale_access_logs_bucket`: Cloud Storage bucket name for access logs (must be globally unique)

1.4 Export the LogScale license as a Terraform environment variable:
```bash
export TF_VAR_humiocluster_license=<your_logscale_license>
```

### Deployment steps

Run the following Terraform commands against each Terraform module in sequence to provision the GKE cluster and deploy the LogScale application:

2.1 **Initialize Terraform**
```bash
terraform init
```

2.2 **Plan the Terraform deployment**
```bash
terraform plan
```
Or you could target a specific module:
```bash
terraform plan -target="module.vpc"
```

2.3 **Deploy VPC**
```bash
terraform apply -target="module.vpc"
```

2.4 **Build GKE cluster**
```bash
terraform apply -target="module.gke"
```

2.5 **Deploy Kubernetes prerequisites**

* Observation: You may need to update the local .kube/config if running this command locally

```bash
gcloud container clusters get-credentials <your-gke-cluster-name> --zone <your-zone> --project <your-project-id>
# Updated context gke_<project>_<zone>_<cluster-name> in /Users/<local_user>/.kube/config
```

```bash
terraform apply -target="module.kubernetes_pre_install"
```

2.6 **Deploy LogScale**
```bash
terraform apply -target="module.logscale"
```

2.7 **Configure DNS Record**
After the deployment completes, create a DNS A record in your DNS provider (e.g., Cloud DNS, Route53, or your domain registrar) pointing your domain to the external load balancer IP:

```bash
# Get the external IP address
terraform output -raw gce-ingress-external-static-ip
```

Create an A record:
- **Name**: Your subdomain (e.g., `logscale`)  
- **Type**: A
- **Value**: The external IP address from the terraform output
- **TTL**: 300 (or your preferred value)

Example DNS record:
```
logscale.your-domain.com   300   IN   A   <EXTERNAL_IP_ADDRESS>
```

## Repository Structure

- **main.tf**: Contains the main Terraform configuration and module definitions for setting up the VPC, GKE, Kubernetes prerequisites, and LogScale.
- **providers.tf**: Configures the necessary providers for the Terraform configuration.
- **variables.tf**: Declares the variables used in the Terraform configuration.
- **outputs.tf**: Specifies the outputs for the Terraform run.
- **locals.tf**: Contains local variables and templates for cluster size configurations.
- **cluster_size.tpl**: Template file specifying the available parameters for different sizes of LogScale clusters.
- **terraform.tfvars**: Variable values for the configuration.
- **versions.tf**: Specifies the required versions of Terraform and providers.

## Cluster Size Configuration

The `cluster_size.tpl` file specifies the available parameters for different sizes of LogScale clusters. This template defines various cluster sizes (e.g., xsmall, small, medium, large, xlarge) and their associated configurations, including node counts, machine types, disk sizes, and resource limits. The Terraform configuration uses this template to dynamically configure the LogScale deployment based on the selected cluster size.

**File**: `cluster_size.tpl`

**Usage**: The data from `cluster_size.tpl` is retrieved and rendered by the `locals.tf` file. The `locals.tf` file uses the `jsondecode` function to parse the template and select the appropriate cluster size configuration based on the `logscale_cluster_size` variable.

**Example**:
```hcl
# Local Variables
locals {
  # Render a template of available cluster sizes
  cluster_size_template = jsondecode(templatefile("${path.module}/cluster_size.tpl", {}))
  cluster_size_rendered = {
    for key in keys(local.cluster_size_template) :
    key => local.cluster_size_template[key]
  }
}
```

## Modules

### VPC Module
This module provisions the necessary networking components for the infrastructure, including VPC, subnets, firewall rules, NAT gateway, and static IP addresses. This setup ensures high availability and fault tolerance for the deployed resources across multiple zones. The module configures security rules to allow only necessary traffic, enhancing the security posture of the deployed environment. Specific firewall rules are defined to control access based on protocol, port range, and source/destination IP addresses. Additionally, for advanced architecture deployments, it creates a dedicated proxy subnetwork for internal load balancing with proper CIDR allocation and firewall rules.

**Source**: `./modules/gcp/vpc`

**Key Features:**
- **Creates VPC Network**: Provisions the main VPC network with custom subnets and private Google access enabled
- **Creates Static IP Addresses**: Provisions static external IP for ingress and NAT egress for outbound connectivity
- **Creates Firewall Rules**: Configures security rules for internal communication and proxy subnet access
- **Creates NAT Gateway**: Sets up Cloud NAT with manual IP allocation for outbound internet access from private nodes
- **Creates Network Router**: Provisions router for NAT configuration with optimized timeout settings
- **Creates Proxy Subnetwork**: Sets up dedicated proxy subnetwork for advanced architecture internal load balancing

**Variables**:
- `project_id`: GCP project ID
- `region`: GCP region for the VPC
- `infrastructure_prefix`: Prefix for naming resources
- `gcp_network_name`: Name of the VPC network
- `gcp_subnetwork_name`: Name of the main subnetwork
- `gcp_cidr_range`: CIDR block for the main subnetwork
- `gcp_subnetwork_proxy_name`: Name of the proxy subnetwork (advanced only)
- `gcp_subnetwork_proxy_cidr_range`: CIDR block for the proxy subnetwork (advanced only)
- `logscale_cluster_type`: Type of LogScale cluster (affects proxy subnetwork creation)
- `gce_ingress_ip_name`: Name for the GCE ingress static IP
- `gcp_network_nat_ip_name`: Name for the NAT egress IP
- `gcp_network_router_name`: Name for the network router
- `gcp_network_router_nat_name`: Name for the router NAT

### GKE Module
Sets up the Google Kubernetes Engine (GKE) cluster and associated resources. This module performs the following tasks:

**Key Features:**
- **Creates Service Accounts**: The module provisions service accounts necessary for GKE cluster operations, including workload identity for LogScale pods to access GCP services securely
- **Creates GKE Cluster**: Provisions the GKE cluster with appropriate configuration for LogScale workloads, including private nodes and authorized networks
- **Creates Node Pools**: Sets up managed node pools based on the cluster architecture (basic, dedicated-ui, or advanced) and size configuration, with auto-scaling enabled
- **Creates Cloud Storage Buckets**: Provisions Cloud Storage buckets for LogScale data storage and access logs with proper IAM bindings
- **Configures Workload Identity**: Sets up workload identity binding for secure access to GCP services without storing service account keys

**Source**: `./modules/gcp/gke`

**Variables**:
- `project_id`: GCP project ID
- `region`: GCP region for the GKE cluster
- `zone`: GCP zone for the GKE cluster
- `logscale_cluster_size`: Size of the LogScale cluster (xsmall, small, medium, large, xlarge)
- `logscale_cluster_type`: Type of the LogScale cluster (basic, dedicated-ui, advanced)
- `cluster_size_definitions`: Cluster size configuration from template
- `network_name`, `subnetwork_name`: VPC networking configuration
- `ip_ranges_allowed_to_kubeapi`: IP ranges allowed to access Kubernetes API

### Kubernetes Pre-install Module
This module deploys Kubernetes resources required before LogScale installation. It creates GCP-specific networking and security components that integrate with Google Cloud services.

**Key Features:**
- **Creates Kubernetes Namespace**: Sets up the logging namespace for LogScale deployment
- **Creates Google Managed Certificates**: Provisions SSL certificates for external ingress using Google's certificate management
- **Creates Backend Configurations**: Sets up health check configurations for GCP load balancers
- **Creates Kubernetes Services**: Provisions NodePort services for external and internal traffic routing
- **Creates GKE Ingresses**: Sets up external ingress for public access and internal ingress for advanced architecture
- **Creates Encryption Secrets**: Generates encryption keys for LogScale data stored in Cloud Storage

**Source**: `./modules/kubernetes/pre-install`

**Variables**:
- `cluster_endpoint`: GKE cluster endpoint
- `cluster_ca_certificate`: Cluster CA certificate
- `logscale_cluster_k8s_namespace_name`: Kubernetes namespace for LogScale
- `public_url`: Public URL for the LogScale cluster
- `gcp_static_ip_name`: Name of the static IP for ingress
- `logscale_cluster_type`: Type of LogScale cluster (affects ingress configuration)

### LogScale Module
Deploys the LogScale application on the GKE cluster using the logscale-kubernetes module. This includes Strimzi Kafka for event streaming, Humio operator for LogScale management, and the complete LogScale cluster configuration.

**Key Features:**
- **Deploys Strimzi Kafka**: Provisions Apache Kafka using the Strimzi operator for reliable event streaming
- **Deploys Humio Operator**: Installs the Humio operator to manage LogScale cluster lifecycle
- **Creates LogScale Cluster**: Provisions the LogScale cluster with appropriate node pools and resource allocation
- **Configures Storage Classes**: Sets up different storage classes for optimal performance (topolvm-provisioner for digest nodes, premium-rwo for UI/Kafka)
- **Sets up TLS**: Configures TLS certificates for secure communication between LogScale components
- **Configures GCP Integration**: Sets up workload identity and environment variables for Cloud Storage access

**Source**: `../logscale-kubernetes`

**Variables**:
- `k8s_cluster_name`: Name of the GKE cluster
- `logscale_cluster_size`: Size of the LogScale cluster
- `logscale_cluster_type`: Type of the LogScale cluster
- `logscale_license`: LogScale license JWT token
- `humio_operator_chart_version`: Version of the Humio operator chart
- `logscale_image_version`: Version of the LogScale container image
- `node_group_definitions`: Cluster size and resource definitions including GCP-specific overrides

## Terraform Variables in terraform.tfvars

| Variable Name | Description | Type | Default Value |
|---------------|-------------|------|---------------|
| project_id | GCP project ID | string | |
| region | GCP region | string | us-central1 |
| zone | GCP zone | string | us-central1-a |
| infrastructure_prefix | Prefix for resource naming | string | logscale |
| public_url | Public URL for LogScale cluster | string | |
| logscale_cluster_type | Type of LogScale cluster (basic/advanced) | string | basic |
| logscale_cluster_size | Size of LogScale cluster | string | xsmall |
| logscale_cluster_k8s_namespace_name | Kubernetes namespace | string | logging |
| gcs_bucket_name | Cloud Storage bucket for LogScale data | string | |
| logscale_access_logs_bucket | Cloud Storage bucket for access logs | string | |
| humio_operator_chart_version | Humio operator chart version | string | 0.29.2 |
| humio_operator_version | Humio operator version | string | 0.29.2 |
| logscale_image_version | LogScale image version | string | 1.207.0 |
| cm_version | Cert-manager version | string | v1.15.1 |
| strimzi_operator_version | Strimzi operator version | string | 0.45.0 |
| humiocluster_license | LogScale license | string | |
| ip_ranges_allowed_to_kubeapi | IP ranges allowed to access Kubernetes API | list(string) | [] |

## Architecture Types

### Basic Architecture (`logscale_cluster_type = "basic"`)
- Single node pool for all LogScale components
- Suitable for development and small-scale deployments  
- Components: All-in-one nodes, Kafka (Strimzi)

### Dedicated UI Architecture (`logscale_cluster_type = "dedicated-ui"`) - **Recommended**
- Separate node pools for UI and core components
- Better resource isolation and scaling
- Components: Core nodes (digest/storage), UI nodes (HTTP-only), Kafka (Strimzi)

### Advanced Architecture (`logscale_cluster_type = "advanced"`)
- Separate node pools for each LogScale component type
- Maximum scalability and resource optimization
- Components: Digest nodes, Ingest nodes, UI nodes, Kafka (Strimzi)
- Includes internal load balancer for ingest traffic

## Cluster Sizes

| Size | Use Case | Core Nodes | UI Nodes | Kafka Nodes | Storage |
|------|----------|------------|----------|-------------|---------|
| **xsmall** | Development, POC | 3 x n2-standard-16 | 3 x e2-highmem-8 | 3 x e2-standard-8 | 2900Gi |
| **small** | Small production | 9 x n2-highmem-16 | 3 x e2-highmem-4 | 6 x e2-standard-8 | 5800Gi |
| **medium** | Medium production | 21 x n2-standard-32 | 6 x n2-standard-8 | 9 x n2-standard-8 | 11500Gi |
| **large** | Large production | 42 x n2-standard-32 | 9 x n2-standard-16 | 9 x n2-standard-16 | 11500Gi |
| **xlarge** | Enterprise | 78 x n2-standard-48 | 9 x n2-standard-16 | 18 x n2-standard-16 | 11500Gi |

## Storage Classes

LogScale GCP uses different storage classes optimized for each component:

- **Core/Digest pods**: `topolvm-provisioner` (high-performance local SSD)
- **UI/Ingest pods**: `premium-rwo` (standard persistent disks)
- **Kafka brokers**: `premium-rwo` (reliable persistent storage)

## Key Features

- ✅ **Auto-scaling**: GKE cluster autoscaling for all node pools
- ✅ **High availability**: Multi-zone deployment with pod anti-affinity
- ✅ **Security**: Workload Identity, private nodes, network policies
- ✅ **SSL/TLS**: Automatic certificate management with google managed certificates
- ✅ **Backup**: Automated backups to Cloud Storage
- ✅ **Updates**: Rolling updates with zero downtime

## Troubleshooting

### Kubernetes Namespace Resource Conflicts
### LogScale-Kubernetes Module Namespace Conflicts

If you encounter namespace conflicts when running modules from the `logscale-kubernetes` repository (error: "resource already exists"), this occurs because the LogScale GCP v2 `kubernetes_pre_install` module creates the `logging` namespace for GCP-specific resources, but the `logscale-kubernetes` module also tries to create the same namespace.

**Error example:**
```
Error: Cannot create resource that already exists
with module.logscale.module.logscale-prereqs.kubernetes_manifest.logscale_ns,
resource "/logging" already exists
```

**Solution:** Import the existing namespace resource in the logscale-kubernetes module.
This tells Terraform to use the existing namespace instead of trying to create a new one.

## Getting Help
If you encounter any issues while using LogScale GCP, you can create an issue on our [Github repo](https://github.com/CrowdStrike/logscale-gcp) for bugs, enhancements, or other requests.

## Contributing
You can contribute by:

* Raising any issues you find using LogScale GCP
* Fixing issues by opening [Pull Requests](https://github.com/CrowdStrike/logscale-gcp/pulls)
* Improving documentation

All bugs, tasks or enhancements are tracked as [GitHub issues](https://github.com/CrowdStrike/logscale-gcp/issues).

## Additional Resources
 - LogScale Introduction: [LogScale Beginner Introduction](https://library.humio.com/training/training-getting-started.html)
 - LogScale Training: [LogScale Overview](https://library.humio.com/training/training-fc.html)
 - More about Falcon LogScale: [Falcon LogScale Services](https://www.crowdstrike.com/services/falcon-logscale/)

## References

- [Cert Manager Documentation](https://cert-manager.io/docs/)
- [Strimzi Documentation](https://strimzi.io/docs/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [LogScale Documentation](https://library.humio.com/)
- [Humio Operator Documentation](https://github.com/humio/humio-operator)
- [LogScale Kubernetes Module](https://github.com/humio/logscale-kubernetes)
- [Deploying LogScale with Operator on Google Cloud Platform (GCP)](https://library.humio.com/falcon-logscale-self-hosted-1.131/installation-containers-kubernetes-gcp-install.html#installation-gcp-ref-arch-refarch)