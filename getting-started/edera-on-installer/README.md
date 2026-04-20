# EderaON Scripts

Scripts for provisioning an AWS EC2 test instance and installing [EderaON](https://on.edera.dev).

## ec2-setup.sh

Automates the steps in the [Prepare Your VM](https://on.edera.dev/prepare-your-vm/) guide. Launches an EC2 instance and optionally installs the dependencies needed for Edera installation.

### Usage

```bash
./ec2-setup.sh [--os OS] [--name NAME] [--key-name KEY_NAME] [--region REGION] [--verbose]
```

### What it does

1. Validates AWS credentials and region
2. Verifies or creates an EC2 key pair
3. Resolves the latest AMI for the selected OS
4. Creates a security group (`<name>-sg`) allowing SSH from your current IP
5. Launches an `m5.large` instance with a 30 GB gp3 root volume
6. Optionally installs runtime dependencies (Docker or Podman, nftables) over SSH

### Options

| Flag | Default | Description |
| --- | --- | --- |
| `--os` | `ubuntu24` | OS to use: `ubuntu24`, `al2023`, `centos9`, `rhel10` |
| `--name` | `ederaon-test` | Instance name tag; security group will be `<name>-sg` |
| `--key-name` | `edera-key` | AWS key pair name, or path to a local private key file |
| `--region` | AWS profile default | AWS region to launch in |
| `--verbose`, `-v` | — | Show full output from dependency installation |

### Requirements

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured
- `AWS_PROFILE` set, or a default profile with credentials and region configured

---

## ec2-teardown.sh

Terminates the test instance created by `ec2-setup.sh` and optionally deletes the associated security group.

### Usage

```bash
./ec2-teardown.sh [--name NAME] [--keep-sg] [--region REGION]
```

### What it does

1. Terminates the instance
2. Waits for termination to complete, then prompts to delete the security group

### Options

| Flag | Default | Description |
| --- | --- | --- |
| `--name` | `ederaon-test` | Name tag of the instance to terminate |
| `--keep-sg` | — | Skip the security group deletion prompt and keep it |
| `--region` | AWS profile default | AWS region to target |

---

## install.sh

A single-script installer for EderaON. Automates the steps in the [Install Edera](https://on.edera.dev/install-edera/) guide.

### Usage

```bash
EDERA_LICENSE_KEY=<your-key> bash install.sh
```

Get your license key at [on.edera.dev](https://on.edera.dev).

### What it does

1. Detects your OS and container runtime (Docker or Podman)
2. Checks for UEFI boot mode
3. Runs `edera-check preinstall` to verify system requirements
4. Authenticates to the Edera registry with your license key
5. Runs the installer container

The machine reboots when installation completes.

### Options

| Flag | Description |
| --- | --- |
| `--verbose`, `-v` | Show full output from edera-check and the installer |

### Supported platforms

Tested on AWS EC2 in UEFI boot mode:

- Ubuntu 24.04 LTS (Docker)
- Amazon Linux 2023 (Docker)
- CentOS Stream 9 (Podman)
- RHEL 10 (Podman)

### Requirements

- UEFI boot mode
- Docker (Ubuntu, AL2023) or Podman (CentOS, RHEL) installed and accessible without sudo
- `EDERA_LICENSE_KEY` environment variable set

### Security

This script runs the Edera installer container with elevated privileges (`--privileged`, `--pid=host`, `--net=host`, `/` mounted to `/host`). These are required to modify the bootloader and install kernel components. Review [`scripts/install.sh`](scripts/install.sh) before running.

See [`SECURITY.md`](../../SECURITY.md) for the project security policy.
