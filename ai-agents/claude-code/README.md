# Run Claude Code with Edera Isolation

Run Anthropic's Claude Code CLI in an Edera-protected Kubernetes pod. Each AI agent operates in its own isolated Linux kernel, containing any unexpected behavior to a single pod.

## Why Isolate AI Agents?

AI coding agents are most useful when they run unrestricted—writing files, executing scripts, installing packages, making API calls. But this creates a security problem: you're giving an AI system broad access to execute arbitrary code.

Edera solves this with per-workload kernel isolation. If an AI agent behaves unexpectedly or is compromised, it's contained within its own kernel—not your cluster.

See [AI Agent Sandboxing](https://docs.edera.dev/technical-overview/concepts/ai-agent-isolation/) for more details.

## Prerequisites

- Kubernetes cluster with Edera nodes
- `kubectl` configured to access the cluster
- Container registry (or use `ttl.sh` for testing)
- Claude account (Pro, Team, or Enterprise) for authentication

## Quick Start

```bash
# Build and push the image
make build push

# Deploy Claude Code pod
make deploy

# Launch Claude Code CLI
make exec
```

## Step-by-Step

### 1. Build the Container Image

The Dockerfile includes Claude Code CLI plus common development tools (Go, Rust, Python, kubectl, gh, ripgrep, jq).

```bash
# Build for amd64 (required for Edera)
docker build --platform linux/amd64 -t claude-code:latest .

# Tag and push to your registry
docker tag claude-code:latest ghcr.io/<your-org>/claude-code:latest
docker push ghcr.io/<your-org>/claude-code:latest
```

For quick testing without a registry, use [ttl.sh](https://ttl.sh):

```bash
docker tag claude-code:latest ttl.sh/claude-code-test:2h
docker push ttl.sh/claude-code-test:2h
```

### 2. Update the Manifest

Edit `claude-code-pod.yaml` and replace the image reference:

```yaml
image: ghcr.io/<your-org>/claude-code:latest
```

### 3. Deploy the Pod

```bash
kubectl apply -f claude-code-pod.yaml
kubectl wait --for=condition=Ready pod/claude-code --timeout=120s
```

### 4. Verify Isolation

Confirm the pod is running in an Edera zone (isolated kernel):

```bash
kubectl exec claude-code -- cat /proc/version
```

Expected output shows the Edera zone kernel (for example, `6.12.x` or `6.15.x`), not your host kernel.

### 5. Launch Claude Code

```bash
kubectl exec -it claude-code -- claude
```

On first run, Claude Code will provide a URL to authenticate via your browser. Complete the OAuth flow to connect your Claude account.

## Verification Commands

| Command | Purpose |
|---------|---------|
| `make verify` | Check kernel isolation is active |
| `make tools` | Verify all development tools are working |
| `make exec` | Interactive shell into the pod |

## Cleanup

```bash
make clean
```

## Persistence

By default, the pod uses `emptyDir` volumes that reset on pod restart. For persistent OAuth credentials and workspace:

1. Create a PersistentVolumeClaim
2. Mount it at `/root/.claude` and `/workspace`

See `claude-code-pod-persistent.yaml` for an example.

## Troubleshooting

**Pod stuck in Pending**: Verify Edera RuntimeClass exists:
```bash
kubectl get runtimeclass edera
```

**Image pull errors**: Ensure you've pushed to the correct registry and the cluster can access it.

**Claude authentication fails**: Check you have an active Claude subscription (Pro, Team, or Enterprise).

## Documentation

- [AI Agent Sandboxing Concept](https://docs.edera.dev/technical-overview/concepts/ai-agent-isolation/)
- [Claude Code Documentation](https://docs.anthropic.com/claude-code)
