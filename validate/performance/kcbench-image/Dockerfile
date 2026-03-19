# Pre-built kcbench image for Edera CPU benchmarking
# Avoids runtime package installation which requires large scratch disk
FROM ubuntu:24.04

# Install kernel build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc \
    bison \
    flex \
    libelf-dev \
    libssl-dev \
    build-essential \
    wget \
    ca-certificates \
    cpio \
    xz-utils \
    time \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Download kcbench script directly
RUN wget -O /usr/local/bin/kcbench https://gitlab.com/knurd42/kcbench/-/raw/master/kcbench \
    && chmod +x /usr/local/bin/kcbench

# Pre-download kernel source to speed up benchmark
# Using kernel 6.6 LTS (smaller than 6.11, still representative)
WORKDIR /workspace
RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.70.tar.xz \
    && mkdir -p /usr/share/kcbench \
    && mv linux-6.6.70.tar.xz /usr/share/kcbench/

# Create workspace directory
RUN mkdir -p /workspace/tmp

WORKDIR /workspace

# Default command runs the benchmark
CMD ["/bin/bash", "-c", "echo '=== Edera CPU Benchmark (kcbench) ===' && echo '' && echo \"CPUs available: $(nproc)\" && kcbench -i 1 -j $(nproc) -s 6.6.70 && echo '' && echo '=== Benchmark Complete ==='"]
