# POV Validation Test Suite

Structured testing framework for validating Edera's security, performance, and operational capabilities during proof of value (POV) evaluations.

## Prerequisites

- Access to a Kubernetes cluster with Edera nodes
- `kubectl` configured to access the cluster
- `helm` installed for optional components (Falco, Grafana, Kyverno)

## Quick Start

```bash
# Install RuntimeClass and verify setup
make setup

# View all available tests
make help
```

## Test Suites

### Security Demonstration

Validates container isolation and escape prevention.

| Test | Command | Description |
|------|---------|-------------|
| Welcome to Edera | `make welcome` | Verify basic zone isolation |
| Leaky Vessel | `make leaky-vessel` | Container escape prevention demo |
| Falco Integration | `make falco-install && make falco-test` | Security monitoring compatibility |

### Performance Validation

Benchmarks network and CPU performance.

| Test | Command | Description |
|------|---------|-------------|
| iperf (Edera) | `make iperf` | Network throughput with Edera |
| iperf (Baseline) | `make iperf-baseline` | Network throughput without Edera |
| kbench (Edera) | `make kbench` | CPU/storage benchmark with Edera |
| kbench (Baseline) | `make kbench-baseline` | CPU/storage benchmark without Edera |

### Operations Integration

Verifies integration with existing tools and workflows.

| Test | Command | Description |
|------|---------|-------------|
| Grafana | `make grafana-install` | Install Prometheus/Grafana stack |
| Kyverno | `make kyverno-install && make kyverno-test` | RuntimeClass auto-assignment |

## Running Individual Tests

You can also apply manifests directly:

```bash
# Security
kubectl apply -f security/welcome-to-edera.yaml

# Performance
kubectl apply -f performance/iperf-server.yaml
kubectl apply -f performance/iperf-client.yaml

# Operations
kubectl apply -f operations/kyverno-edera-policy.yaml
```

## Cleanup

```bash
# Remove specific test resources
make clean-security
make clean-performance
make clean-operations

# Remove all test resources
make clean
```

## Documentation

For detailed test procedures and expected results, see the [POV Validation Guide](https://docs.edera.dev/guides/pov-validation/).

## File Structure

```
pov-validation/
├── Makefile
├── README.md
├── security/
│   ├── welcome-to-edera.yaml
│   ├── leaky-vessel-test.yaml
│   ├── leaky-vessel-no-edera.yaml
│   └── falco-test.yaml
├── performance/
│   ├── iperf-server.yaml
│   ├── iperf-client.yaml
│   ├── iperf-baseline.yaml
│   ├── kbench-edera.yaml
│   └── kbench-baseline.yaml
└── operations/
    ├── edera-servicemonitor.yaml
    ├── kyverno-edera-policy.yaml
    └── auto-edera-test.yaml
```
