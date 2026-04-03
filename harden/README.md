# Edera production hardening examples

Working examples for hardening an Edera deployment for production. Covers Kyverno admission policies, network policies, and AI agent configuration.

For step-by-step instructions, see the [hardening guide](https://docs.edera.dev/guides/security/harden-for-production/).

## Prerequisites

- Kubernetes cluster with Edera nodes
- `kubectl` configured to access the cluster
- [Kyverno](https://kyverno.io/) installed for admission policies

## Quick start

```bash
# Apply Kyverno hardening policies
make apply-policies

# Apply default-deny egress to a namespace
make apply-network-policy NAMESPACE=your-namespace

# Deploy the AI agent example
make apply-ai-agent

# Verify policies are enforced
make verify
```

## File structure

```
harden/
├── Makefile
├── README.md
├── policies/
│   ├── kyverno-edera-hardening.yaml       - Admission policies (hostPath, host namespaces, capabilities)
│   └── network-policy-default-deny-egress.yaml  - Default-deny egress for tenant namespaces
└── examples/
    └── ai-agent-pod.yaml                  - Hardened AI agent pod configuration
```
