# Workshop cluster setup: add EderaON + Agent Sandbox to a running cluster

This turns a stock Kubernetes node into the cluster the
[code-interpreter agent](./README.md) runs on. You **install EderaON on top of an
already-running cluster** — that's the workshop's whole point: watch a host become
hypervisor-isolated, live, without rebuilding the cluster underneath it.

The flow: install EderaON (it reboots and takes over the container runtime) →
confirm the cluster comes back → register the Edera RuntimeClass → install local
block storage → install the Agent Sandbox controller → run the agent.

Validated in place on an Ubuntu 24.04 / kubeadm / containerd node (k8s v1.35),
EderaON `on-preview`, Agent Sandbox `v0.5.0rc1`.

## Starting point

The workshop box is pre-provisioned with:

- **Ubuntu 24.04**, booted in **UEFI** mode (EderaON requires UEFI; Secure Boot
  must be **off** — the installer rewrites the bootloader).
- A single-node **kubeadm cluster on containerd** (the node is `Ready`).
- **Docker**, usable without `sudo` (the EderaON installer runs as a container).

Confirm before you start:

```bash
[ -d /sys/firmware/efi ] && echo "UEFI ok"   # must print
kubectl get nodes                             # node Ready, on containerd
docker ps                                     # works without sudo
```

You'll also need an **EderaON license key** — get one at
[on.edera.dev](https://on.edera.dev/).

> **License keys are per-machine.** Activation happens at runtime against
> `license.edera.dev` and is *separate* from the registry login the installer does.
> A key already activated on another machine returns `403 LICENSE_FORBIDDEN` and
> the daemon will crash-loop. Use a fresh key per box.

## Step 1: Install EderaON (on top of the running cluster)

Run the installer from [`getting-started/edera-on-installer`](../../getting-started/edera-on-installer/).
It runs pre-install checks, takes over the container runtime, and **reboots**.

```bash
EDERA_LICENSE_KEY=<your-key> bash install.sh --yes
```

What it does to the cluster: it repoints the kubelet from containerd to Edera's
CRI socket (`/var/lib/edera/protect/cri.socket`) and reboots. On the way back up
the node runs the `-edera` kernel and every pod is scheduled through Edera.

> The optional **IOMMU** pre-install check fails on most cloud VMs (no passthrough
> IOMMU) — that's expected and harmless. Only *required* checks must pass.

## Step 2: Confirm the cluster recovered

After the reboot, reconnect and wait for the Edera services and the control plane
to come back (the apiserver can't return until `protect-cri` is active):

```bash
uname -r                                   # ends in -edera
systemctl is-active protect-daemon protect-cri
kubectl get nodes                          # Ready again, now under Edera's CRI
```

If `protect-daemon` is stuck `activating`, check its license activation:

```bash
sudo journalctl -u protect-daemon -n 20 | grep -i licens
# "licensed: machine fingerprint=…" = good
# "403 LICENSE_FORBIDDEN"            = bad key (see the per-machine note above)
```

## Step 3: Register the Edera RuntimeClass

```bash
kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml
kubectl label nodes --all runtime=edera --overwrite
kubectl get runtimeclass edera
```

## Step 4: Local block storage

The single node has no cloud volume driver, so install
[local-path-provisioner](https://github.com/rancher/local-path-provisioner) and
make it the default StorageClass.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass   # local-path should be (default)
```

## Step 5: Install the Agent Sandbox controller + extensions

The agent uses `SandboxTemplate` and `SandboxWarmPool`, which come from the
**extensions** manifest — install both. Pin a `v1beta1` release (`v0.5.0rc1`+).

```bash
export ASB=v0.5.0rc1
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/$ASB/manifest.yaml
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/$ASB/extensions.yaml
kubectl -n agent-sandbox-system rollout status deploy/agent-sandbox-controller
```

## Step 6: Deploy the sandbox-router

The Python SDK's tunnel mode connects through the sandbox-router. Deploy it into
`agent-sandbox-system` (the SDK's default router namespace) with the prebuilt
image — no build required.

```bash
ROUTER_IMAGE=us-central1-docker.pkg.dev/k8s-staging-images/agent-sandbox/sandbox-router:latest-main
curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/agent-sandbox/$ASB/clients/python/agentic-sandbox-client/sandbox-router/sandbox_router.yaml \
  | sed "s|\${ROUTER_IMAGE}|$ROUTER_IMAGE|g" \
  | kubectl apply -n agent-sandbox-system -f -

# The router refuses to start without auth. For a throwaway workshop cluster,
# run it unauthenticated. (For anything real, set ROUTER_AUTH_TOKEN instead.)
kubectl set env deploy/sandbox-router-deployment -n agent-sandbox-system ALLOW_UNAUTHENTICATED_ROUTER=true
kubectl -n agent-sandbox-system rollout status deploy/sandbox-router-deployment
```

## Step 7: Install the local tooling

```bash
sudo apt-get install -y python3-venv git make
```

- `python3-venv` — the example runs the agent in a virtualenv.
- `git` — the SDK installs from a git tag (the PyPI release still targets the
  older v1alpha1 API; see [requirements.txt](./requirements.txt)).
- `make` — drives the targets below (not preinstalled on the base image).

## Verify

From the [`code-interpreter`](./README.md) directory:

```bash
make check    # creates a sandbox, runs code in it, prints its kernel
```

A passing run prints `exit_code: 0` and a sandbox kernel **without** the `-edera`
suffix — i.e. the sandbox runs in its own Edera zone, a different kernel than the
host's `uname -r`. That difference is the whole point: the agent's tool call
executed in a kernel that is not the node's.

## Reset

`make clean` removes the template, warm pool, and any sandboxes, leaving the
cluster in place for another run.
