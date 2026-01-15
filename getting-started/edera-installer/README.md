# Edera Manual Installation - Complete Example

This example provides scripts for installing Edera on any Linux node. It's designed for users who want direct control over the installation process or need to install Edera on existing infrastructure.

## What This Example Provides

- **Installation Scripts**: Automated scripts to install Edera on remote nodes
- **RuntimeClass Configuration**: Kubernetes RuntimeClass for Edera pods
- **Test Workload**: Sample nginx pod using Edera runtime
- **Makefile Automation**: Simple commands for deploy, test, and cleanup

## Quick Start

### Standalone (no Kubernetes)

```bash
# 1. Save your GAR key as key.json
cp /path/to/your/key.json .

# 2. Install Edera on your node
INSTALLER_IP=<node-ip> make deploy

# 3. Verify installation (after reboot completes)
INSTALLER_IP=<node-ip> make test-standalone
```

### With Kubernetes

```bash
# 1. Save your GAR key as key.json
cp /path/to/your/key.json .

# 2. Install Edera on your node
INSTALLER_IP=<node-ip> make deploy

# 3. Configure Kubernetes RuntimeClass
make configure

# 4. Test with a pod
make test
```

### Cloud instances (EC2, GCE, etc.)

For cloud instances that use non-root SSH users:

```bash
INSTALLER_IP=<node-ip> SSH_USER=ubuntu SSH_KEY=~/.ssh/my-key.pem make deploy
INSTALLER_IP=<node-ip> SSH_USER=ubuntu SSH_KEY=~/.ssh/my-key.pem make test-standalone
```

## Prerequisites

Before starting, ensure you have:

1. **Edera Access**: Contact [support@edera.dev](mailto:support@edera.dev) for:
   - Google Artifact Registry (GAR) key for pulling Edera images

2. **SSH Access**: Root SSH access to your target node(s)

3. **Container Runtime**: Docker or nerdctl installed on the target node

4. **kubectl** (optional): For Kubernetes deployments

   ```bash
   kubectl version --client
   ```

## Configuration

### Required: GAR Key

Save your Google Artifact Registry key as `key.json` in this directory:

```bash
cp /path/to/your/key.json .
```

### Target Node Requirements

The target node must have:

- Linux operating system
- Root SSH access
- Docker or nerdctl installed
- Network access to `us-central1-docker.pkg.dev`

## Deployment

### Step-by-Step

```bash
# 1. Install Edera on a node
INSTALLER_IP=<node-ip> make deploy

# 2. Configure Kubernetes RuntimeClass
make configure

# 3. Label your nodes
kubectl label nodes <node-name> runtime=edera

# 4. Test the deployment
make test
```

### Installing Multiple Nodes

Run the deploy command for each node:

```bash
INSTALLER_IP=192.168.1.10 make deploy
INSTALLER_IP=192.168.1.11 make deploy
INSTALLER_IP=192.168.1.12 make deploy
```

### Manual Installation

If you prefer not to use the Makefile:

```bash
# Copy files to target node
scp key.json root@<node-ip>:/tmp/
scp scripts/edera-install.sh root@<node-ip>:~

# SSH to node and run installer
ssh root@<node-ip> 'chmod +x ~/edera-install.sh && ~/edera-install.sh'

# Apply RuntimeClass (Kubernetes only)
kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml

# Label nodes
kubectl label nodes <node-name> runtime=edera

# Deploy test workload
kubectl apply -f kubernetes/test-workload.yaml
```

## Verification

### Automatic Verification

```bash
make verify
```

This checks:

- Cluster nodes are online
- RuntimeClass is configured
- Test workload is running

### Manual Verification

```bash
# Check cluster status
kubectl get nodes -o wide

# Verify Edera RuntimeClass
kubectl get runtimeclass edera

# Check node labels
kubectl get nodes --show-labels | grep runtime=edera

# Verify test pod
kubectl get pods -n edera-test
kubectl get pod edera-test-pod -n edera-test -o jsonpath="{.spec.runtimeClassName}"
```

## Cleanup

### Remove Test Resources Only

```bash
make clean
```

## Troubleshooting

### Common Issues

#### SSH Permission Denied

If you see `Permission denied (publickey)`, specify the SSH user and key:

```bash
INSTALLER_IP=<node-ip> SSH_USER=ubuntu SSH_KEY=~/.ssh/my-key.pem make deploy
```

Common SSH users by platform:
- **EC2 Ubuntu**: `ubuntu`
- **EC2 Amazon Linux**: `ec2-user`
- **GCE**: Your Google account username
- **Azure**: The admin username you specified

#### Make deploy shows "Error 255"

This is expected. The installer reboots the node when complete, which closes the SSH connection. Wait 1-2 minutes for the node to come back online, then run `make test-standalone` to verify.

#### Installation Fails

- Verify SSH access: `ssh -i <key> <user>@<node-ip>`
- Check container runtime: `ssh -i <key> <user>@<node-ip> 'docker --version || nerdctl --version'`
- Verify GAR key is valid and has appropriate permissions

#### Pod Stuck in Pending (Kubernetes)

```bash
kubectl describe pod edera-test-pod -n edera-test
```

Check for:

- Missing `runtime=edera` labels on nodes
- RuntimeClass not installed
- Node capacity issues

#### Container Login Fails

- Verify `key.json` is a valid GAR service account key
- Check network access to `us-central1-docker.pkg.dev`

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

3. **Contact Support**: [support@edera.dev](mailto:support@edera.dev)

## Next Steps

- Deploy your own applications using `runtimeClassName: edera`
- Explore [Edera documentation](https://docs.edera.dev)
- Check out other examples in this repository

## Files

- `Makefile` - Automation commands
- `scripts/install.sh` - Remote installation wrapper
- `scripts/edera-install.sh` - Node installation script
- `kubernetes/test-workload.yaml` - Test pod configuration
