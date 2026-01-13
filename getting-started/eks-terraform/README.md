# EKS with Terraform - Complete Example

This example deploys a complete Amazon EKS cluster with Edera using Terraform. It creates everything from scratch including VPC, subnets, security groups, and EKS cluster with Edera-protected worker nodes.

## 🎯 What This Example Creates

- **VPC**: New VPC with public/private subnets across 2 AZs
- **EKS Cluster**: Latest Kubernetes version with public API endpoint
- **Managed Node Group**: Worker nodes using Edera AMIs with proper labels
- **RuntimeClass**: Edera runtime configuration for pod scheduling
- **Test Workload**: Sample nginx pod using Edera runtime
- **Verification**: Automated scripts to validate the deployment

## ⚡ Quick Start

```bash
# 1. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars with the Edera account ID
vim terraform.tfvars

# 3. Deploy everything
make deploy

# 4. Test the deployment
make test
```

That's it! Your EKS cluster with Edera protection will be ready in ~15 minutes.

## 📋 Prerequisites

Before starting, ensure you have:

1. **Edera Access**: Contact [support@edera.dev](mailto:support@edera.dev) for:
   - Edera AWS account ID
   - AMI access permissions

2. **AWS CLI**: Configured with appropriate permissions for:
   - EC2 (AMI access, VPC management)
   - EKS (cluster and node group management)
   - IAM (service roles and policies)

3. **Terraform or OpenTofu**

   ```bash
   terraform --version
   # OR
   tofu --version
   ```

4. **kubectl**: For testing and verification

   ```bash
   kubectl version --client
   ```

## 🔧 Configuration

### Required Configuration

Edit `terraform.tfvars` with the Edera account ID:

```hcl
# Required: The Edera AWS account ID (provided by Edera team)
edera_account_id = "123456789012"
```

### Optional Configuration

Customize these values in `terraform.tfvars`:

```hcl
# Cluster settings
cluster_name    = "my-edera-cluster"
cluster_version = "1.32"
region          = "us-west-2"  # or us-gov-west-1 for GovCloud

# Node group settings
instance_types = ["m5n.xlarge"]
desired_size   = 2
min_size       = 1
max_size       = 3

# SSH access (optional)
enable_ssh_access = true
ssh_key_name     = "my-ec2-keypair"
```

### SSH Access (Optional)

By default, the EKS nodes are deployed without SSH access for security. To enable SSH access:

```hcl
enable_ssh_access = true
ssh_key_name     = "your-existing-ec2-keypair"
```

**Prerequisites for SSH:**

- An existing EC2 key pair in the same region
- The key pair name specified in `ssh_key_name`

**Creating an EC2 key pair:**

```bash
aws ec2 create-key-pair --key-name edera-eks-key --query 'KeyMaterial' --output text > edera-eks-key.pem
chmod 400 edera-eks-key.pem
```

**Connecting via SSH:**

```bash
# Get node public IPs (when using public subnets)
kubectl get nodes -o wide

# SSH to node
ssh -i edera-eks-key.pem ec2-user@<node-public-ip>
```

### GovCloud Support

This example works with both regular AWS regions and AWS GovCloud:

**For regular AWS:**

```hcl
region = "us-west-2"
```

**For AWS GovCloud:**

```hcl
region = "us-gov-west-1"
```

Simply set the region in `terraform.tfvars` - no other changes needed.

## 🚀 Deployment

### Step-by-Step

```bash
# 1. Initialize Terraform
make init

# 2. Review the plan
make plan

# 3. Deploy infrastructure
make deploy

# 4. Configure kubectl and test
make test
```

### Using Terraform/OpenTofu Directly

The Makefile automatically detects and uses either `terraform` or `tofu` (OpenTofu). If you prefer direct commands:

```bash
# With Terraform
terraform init
terraform plan
terraform apply -auto-approve

# With OpenTofu
tofu init
tofu plan
tofu apply -auto-approve

# Configure kubectl
aws eks --region us-west-2 update-kubeconfig --name edera-cluster

# Apply RuntimeClass
kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml

# Deploy test workload
kubectl apply -f kubernetes/test-workload.yaml
```

## ✅ Verification

The deployment includes comprehensive verification:

### Automatic Verification

```bash
make verify
```

This checks:

- ✅ All nodes are running Edera AMIs
- ✅ Nodes have correct `runtime=edera` labels
- ✅ RuntimeClass is properly configured
- ✅ Test workload is running with Edera runtime

### Manual Verification

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Verify Edera RuntimeClass
kubectl get runtimeclass edera

# Check node labels
kubectl get nodes --show-labels | grep runtime=edera

# Verify test pod
kubectl get pods -n edera-test
kubectl get pod edera-test-pod -n edera-test -o jsonpath="{.spec.runtimeClassName}"
```

### AMI Verification

Run the detailed AMI verification script:

```bash
./scripts/verify-ami.sh
```

This script:

- Lists AMI ID and name for each node
- Confirms nodes are using Edera AMIs
- Validates node labels and RuntimeClass configuration
- Shows test workload status

## 🧹 Cleanup

### Remove Test Resources Only

```bash
make clean
```

### Destroy Everything

```bash
make destroy
```

⚠️ **Warning**: This will permanently delete the entire infrastructure including the EKS cluster, VPC, and all data.

## 🔍 Troubleshooting

### Common Issues

#### Pod Stuck in Pending

```bash
kubectl describe pod edera-test-pod -n edera-test
```

Check for:

- Missing `runtime=edera` labels on nodes
- RuntimeClass not installed
- Node capacity issues

#### AMI Not Found

- Verify the Edera account ID is correct
- Ensure you have access to Edera AMIs
- Check you're in a supported region (us-west-2 or us-gov-west-1)

#### Authentication Issues

```bash
aws sts get-caller-identity
aws eks --region us-west-2 describe-cluster --name edera-cluster
```

### Getting Help

1. **Check Logs**:

   ```bash
   kubectl logs edera-test-pod -n edera-test
   ```

2. **Describe Resources**:

   ```bash
   kubectl describe pod edera-test-pod -n edera-test
   kubectl describe node
   ```

3. **Terraform State**:

   ```bash
   terraform show
   terraform output
   ```

4. **Contact Support**: [support@edera.dev](mailto:support@edera.dev)

## 📊 Outputs

After deployment, Terraform provides these useful outputs:

```bash
terraform output
```

- `cluster_endpoint` - EKS API server endpoint
- `cluster_name` - Name of the EKS cluster
- `configure_kubectl` - Command to configure kubectl
- `edera_ami_id` - AMI ID used for worker nodes
- `edera_ami_name` - AMI name used for worker nodes

## 🏗️ Architecture

This example creates:

```
┌─────────────────────┐
│       Internet      │
└──────────┬──────────┘
           │
    ┌──────▼──────┐
    │   Internet  │
    │   Gateway   │
    └──────┬──────┘
           │
┌──────────▼──────────┐
│     Public Subnets  │
│  ┌───────────────┐  │
│  │   NAT Gateway │  │
│  └───────────────┘  │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│    Private Subnets  │
│  ┌───────────────┐  │
│  │  EKS Cluster  │  │
│  │  ┌─────────┐  │  │
│  │  │ Worker  │  │  │
│  │  │ Nodes   │  │  │
│  │  │(Edera   │  │  │
│  │  │ AMI)    │  │  │
│  │  └─────────┘  │  │
│  └───────────────┘  │
└─────────────────────┘
```

## 🔗 Next Steps

- Deploy your own applications using `runtimeClassName: edera`
- Explore [Edera documentation](https://docs.edera.dev)
- Check out other examples in this repository
- Join our community discussions

## 📄 Files

- `main.tf` - Main Terraform configuration
- `variables.tf` - Input variables and defaults
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Configuration template
- `Makefile` - Automation commands
- `kubernetes/test-workload.yaml` - Test pod and service
- `scripts/verify-ami.sh` - Verification script
