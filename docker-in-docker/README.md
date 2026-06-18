# Docker in Docker: Edera vs runC demo

Running `docker build` inside Kubernetes is one of the most common reasons
teams grant `privileged: true` to a pod. CI pipelines need to build container
images, and Docker-in-Docker (DinD) is the used by GitLab CI, Jenkins, 
Drone, and countless custom runners. Unpriviledged container build alternatives
exist, but lack full Dockerfile compatibility. 

The Docker daemon needs access to cgroups, namespaces, and device nodes to 
function, and in Kubernetes that means `privileged: true` on the DinD sidecar.

The trouble is that on the default container runtime (runc), `privileged: true`
doesn't just grant access to the container's own kernel features. It grants
*ull root access to the underlying node. Any process inside that container
can read every file on the host, see every other tenant's processes, steal
secrets from neighboring pods, and write to the host filesystem. No exploits 
required. Running DinD on runc is a real risk to your other workloads.

## What this demo does

This demo runs a CI pipeline, first against runC, then Edera, using a 
two container pod. The ci-job container builds a python web service, 
runs a multi-stage Docker build, and tests the results. a DinD sidecar 
container provides the Docker  daemon that makes it possble, with the 
required `privileged: true`.

Then we run an escape script, that shows what else can be accessed from
the Docker sidecar, when using the runC and Edera runtimes. 

## What you'll see

### Docker on runc: the escapable build system

The CI pod builds `tenant-a-api` from source using `docker build` with a
multi-stage Dockerfile (Python base, dependency install, copy app, healthcheck).
The build completes, the smoke test passes, timing is printed.

Then, from the same privileged DinD container that made the build possible:

- Reads the host's `/etc/shadow` (password hashes)
- Lists every process on the node, including other tenants' workloads
- Steals Tenant B's database password and API key from `/proc`
- Reads kubelet credentials from the host filesystem
- Writes arbitrary files to the host (full node compromise)

All of this using `nsenter` — a standard Linux tool, not an exploit.

### Docker on Edera: fast and safe

The exact same pod, same `privileged: true`, same Docker build. The CI
job produces the same image, the smoke test passes, timing is printed.

But the escape script hits a wall. Every `nsenter` call reaches the
VM's kernel, not the host. There's nothing to steal, no node to
compromise. The pod is a VM. That's the boundary.

## Prerequisites

- A Kubernetes cluster with Edera Containers installed
  (e.g., via `edera-deploy` DaemonSet, or AKS / GKE with Edera node pools)
- `kubectl` configured with cluster-admin access
- For the Edera build, run `run-demo.sh` **on the node** with `sudo` available —
  it provisions a local loopback block device for Docker storage (single-node
  testing only; see [Docker storage on Edera](#docker-storage-on-edera-single-node-demo-only))

## Quick start

```bash
# Run the full demo end-to-end (runc escape, then Edera isolation)
./run-demo.sh both

# Or run each part individually
./run-demo.sh runc
./run-demo.sh edera

# Clean up
./run-demo.sh cleanup
```

## Step-by-step walkthrough

### 1. Set up the environment

```bash
kubectl apply -f manifests/00-namespaces.yaml
kubectl apply -f manifests/01-ci-build-source.yaml
kubectl apply -f manifests/02-tenant-b-victim.yaml
```

Wait for Tenant B's pod:

```bash
kubectl -n tenant-b wait --for=condition=Ready pod/victim-app --timeout=60s
```

### 2. Deploy the runc CI runner and watch the build

```bash
kubectl apply -f manifests/03-tenant-a-dind-runc.yaml
kubectl -n tenant-a wait --for=condition=Ready pod/ci-runner-runc --timeout=120s
```

Watch the Docker build happen in real time:

```bash
kubectl -n tenant-a logs ci-runner-runc -c ci-job -f
```

The multi-stage build pulls `python:3.12-alpine`, installs
dependencies, the app, launches the built image, verifies 
it comes up healthy, and prints timing information.

### 3. Demonstrate the escape

Now exec into the privileged `dind` container that made
the build possible and run the escape script:

```bash
kubectl cp scripts/escape-demo.sh tenant-a/ci-runner-runc:/tmp/escape-demo.sh -c dind
kubectl -n tenant-a exec -it ci-runner-runc -c dind -- sh /tmp/escape-demo.sh
```

Every test will show `ESCAPED` in red. The same sidecar that built
your image can also read every secret on the node.

### 4. Deploy the Edera version and repeat

```bash
kubectl apply -f manifests/04-tenant-a-dind-edera.yaml
kubectl -n tenant-a wait --for=condition=Ready pod/ci-runner-edera --timeout=180s
```

Watch the build again, it completes the same way:

```bash
kubectl -n tenant-a logs ci-runner-edera -c ci-job -f
```

Run the escape script:

```bash
kubectl cp scripts/escape-demo.sh tenant-a/ci-runner-edera:/tmp/escape-demo.sh -c dind
kubectl -n tenant-a exec -it ci-runner-edera -c dind -- sh /tmp/escape-demo.sh
```

Every test will show `CONTAINED` in green.

## Comparing build times

Both pods time every phase of the pipeline. The timing summary 
prints at the end of the ci-job logs:

```bash
kubectl -n tenant-a logs ci-runner-runc -c ci-job | grep -A8 "TIMING SUMMARY"
kubectl -n tenant-a logs ci-runner-edera -c ci-job | grep -A8 "TIMING SUMMARY"
```

`./run-demo.sh both` prints a side-by-side comparison table at the end with
the delta for each phase. Edera holds its own.

## Cleanup

```bash
kubectl delete -f manifests/ --ignore-not-found
```
