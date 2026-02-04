FROM node:22-bookworm

# Versions (pin for reproducibility)
ARG GO_VERSION=1.23.6
ARG RUST_PROFILE=minimal
ARG KUBECTL_VERSION=1.32.0
ARG DOCKER_VERSION=27.5.1
ARG GH_VERSION=2.67.0
ARG RIPGREP_VERSION=14.1.1
ARG JQ_VERSION=1.7.1

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client \
    python3 python3-pip python3-venv \
    make gcc g++ \
    curl wget tree less vim-tiny htop \
    procps net-tools iproute2 dnsutils iputils-ping netcat-openbsd \
    ca-certificates gnupg unzip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf python3 /usr/bin/python \
    && ln -sf vim.tiny /usr/bin/vim

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Install Go
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    | tar xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/root/go"

# Install Rust
ENV RUSTUP_HOME="/usr/local/rustup"
ENV CARGO_HOME="/usr/local/cargo"
ENV PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain stable --profile ${RUST_PROFILE} --no-modify-path

# Install kubectl
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# Install Docker CLI
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" | \
    tar xz -C /tmp && mv /tmp/docker/docker /usr/local/bin/docker && rm -rf /tmp/docker

# Install GitHub CLI
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" | \
    tar xz -C /tmp && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh && rm -rf /tmp/gh_*

# Install ripgrep and jq
RUN curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz" | \
    tar xz -C /tmp && mv /tmp/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg /usr/local/bin/rg && rm -rf /tmp/ripgrep-*

RUN curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
    -o /usr/local/bin/jq && chmod +x /usr/local/bin/jq

WORKDIR /workspace
CMD ["bash"]
