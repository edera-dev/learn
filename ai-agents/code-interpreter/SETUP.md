# Workshop cluster setup: EderaON on GCE with kubeadm

This builds the self-contained cluster the
[code-interpreter agent](./README.md) runs on: a single Google Compute Engine VM
running [EderaON](https://on.edera.dev/), a `kubeadm` Kubernetes cluster using
Edera's container runtime, local block storage, and the Agent Sandbox controller.

Everything runs on one VM — no managed control plane, no cloud load balancer, no
cloud block-storage driver. That keeps the workshop portable and cheap to tear
down.

These steps were validated on `e2-standard-8` / Ubuntu 24.04 with EderaON
`on-preview`, Kubernetes v1.33, and Agent Sandbox `v0.5.0rc1`.

## Prerequisites

- A GCP project and the `gcloud` CLI, authenticated (`gcloud auth login`).
- An **EderaON license key** — get one at [on.edera.dev](https://on.edera.dev/).
- `kubectl` locally (optional; you can run everything over SSH on the VM).

Pick names once:

```bash
export PROJECT=$(gcloud config get-value project)
export ZONE=us-west1-a
export VM=ederaon-workshop
```

## Step 1: Create the GCE instance

EderaON requires **UEFI boot**. Enabling the shielded-VM vTPM boots the instance
in UEFI mode. Do **not** enable Secure Boot — the installer modifies the
bootloader to boot the Edera hypervisor.

```bash
gcloud compute instances create "$VM" \
  --zone="$ZONE" \
  --machine-type=e2-standard-8 \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=50GB --boot-disk-type=pd-balanced \
  --shielded-vtpm --shielded-integrity-monitoring
```

> EderaON runs as a type-1 hypervisor via paravirtualization, so it works on a
> standard GCE instance — no nested-virtualization-enabled machine type needed.

SSH in (all remaining steps run on the VM):

```bash
gcloud compute ssh "$VM" --zone="$ZONE"
```

## Step 2: Install Docker

The EderaON installer runs as a container and must reach Docker without `sudo`.

```bash
sudo apt-get update -qq
sudo apt-get install -y docker.io
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker
```

Log out and back in (`exit`, then `gcloud compute ssh` again) so your shell picks
up the `docker` group, then confirm `docker ps` works without `sudo`.

## Step 3: Install EderaON

Copy your license key to the VM (keep it out of your shell history), then run the
installer from this repo. The installer modifies the bootloader, installs the
hypervisor, and **reboots**.

```bash
# From the repo: getting-started/edera-on-installer/scripts/install.sh
EDERA_LICENSE_KEY=<your-key> bash install.sh --yes
```

After the reboot, reconnect and confirm the host now runs the Edera kernel and
the protect services are up:

```bash
uname -r                                   # ends in -edera
systemctl is-active protect-daemon protect-cri
ls /var/lib/edera/protect/cri.socket       # Edera's CRI endpoint
```

EderaON pre-points the kubelet at its CRI socket — `/etc/default/kubelet` already
contains `--container-runtime-endpoint=unix:///var/lib/edera/protect/cri.socket`.

## Step 4: Install Kubernetes (kubeadm)

```bash
# Kernel prerequisites
sudo swapoff -a
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf
sudo modprobe overlay br_netfilter
printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\nnet.ipv4.ip_forward=1\n' \
  | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system

# Kubernetes apt repo (v1.33)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -qq

# Install. --force-confold keeps EderaON's kubelet CRI config (avoids an
# interactive conffile prompt on /etc/default/kubelet).
sudo apt-get install -y -o Dpkg::Options::="--force-confold" kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

## Step 5: Initialize the cluster

Point kubeadm at Edera's CRI socket:

```bash
sudo kubeadm init \
  --cri-socket=unix:///var/lib/edera/protect/cri.socket \
  --pod-network-cidr=10.244.0.0/16

# kubeconfig for your user
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# CNI (flannel) and untaint the single node so it can run workloads
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

Wait for the node to become `Ready` (`kubectl get nodes`).

## Step 6: Register the Edera RuntimeClass

```bash
kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml
kubectl label nodes --all runtime=edera --overwrite
kubectl get runtimeclass edera
```

## Step 7: Local block storage

The single node has no cloud block-storage driver, so install
[local-path-provisioner](https://github.com/rancher/local-path-provisioner) and
make it the default StorageClass. Sandboxes that request a PVC then get a volume
backed by the node's local disk.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass   # local-path should be (default)
```

## Step 8: Install the Agent Sandbox controller + extensions

The code-interpreter agent uses `SandboxTemplate` and `SandboxWarmPool`, which
come from the **extensions** manifest — install both. Pin a `v1beta1` release
(`v0.5.0rc1`+).

```bash
export ASB=v0.5.0rc1
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/$ASB/manifest.yaml
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/$ASB/extensions.yaml
kubectl -n agent-sandbox-system rollout status deploy/agent-sandbox-controller
```

## Step 9: Deploy the sandbox-router

The Python SDK's tunnel mode connects through the sandbox-router. Deploy it into
`agent-sandbox-system` (the SDK's default router namespace) using the prebuilt
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

## Step 10: Python prerequisites

```bash
sudo apt-get install -y python3-venv git
```

`git` is needed because the agent installs the Agent Sandbox SDK from its git tag
(the PyPI release still targets the older v1alpha1 API). See
[requirements.txt](./requirements.txt).

## Verify

You're ready. From the [`code-interpreter`](./README.md) directory:

```bash
make check    # creates a sandbox, runs code in it, prints its kernel
```

A passing run prints `exit_code: 0` and a sandbox kernel **without** the `-edera`
suffix — i.e. the sandbox is running in its own Edera zone, a different kernel
than the host's `uname -r`.

## Teardown

```bash
gcloud compute instances delete "$VM" --zone="$ZONE"
```
