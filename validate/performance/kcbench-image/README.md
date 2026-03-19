# kcbench Docker Image

Pre-built image for CPU benchmarking with kcbench in Edera zones.

## Why?

Edera zones have limited root filesystem by default (~100MB with tmpfs). Installing
build dependencies at runtime requires gigabytes of space. This image pre-installs
everything so the benchmark runs without needing package installation.

## Build and Push

```bash
# Build the image
docker build -t kcbench-prebuilt:latest .

# Tag for your registry (example: Docker Hub)
docker tag kcbench-prebuilt:latest yourusername/kcbench-prebuilt:latest

# Or for ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-west-2.amazonaws.com
docker tag kcbench-prebuilt:latest <account>.dkr.ecr.us-west-2.amazonaws.com/kcbench-prebuilt:latest
docker push <account>.dkr.ecr.us-west-2.amazonaws.com/kcbench-prebuilt:latest
```

## What's Included

- Ubuntu 24.04 base
- kcbench benchmark tool
- Full GCC toolchain (build-essential)
- Kernel build dependencies (bc, bison, flex, libelf-dev, libssl-dev)
- Pre-downloaded Linux 6.6.70 kernel source (~135MB)

## Usage

```bash
# Run directly
docker run --rm kcbench-prebuilt:latest

# Or with custom options
docker run --rm kcbench-prebuilt:latest kcbench -i 1 -j 4 -s 6.6.70
```
