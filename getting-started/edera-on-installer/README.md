# EderaON Installer Script

A single-script installer for [EderaON](https://on.edera.dev) on AWS EC2. Automates the steps in the [Install Edera](https://on.edera.dev/install-edera/) guide.

## Usage

```bash
EDERA_LICENSE_KEY=<your-key> bash install.sh
```

Get your license key at [on.edera.dev](https://on.edera.dev).

## What it does

1. Detects your OS and container runtime (Docker or Podman)
2. Checks for UEFI boot mode
3. Runs `edera-check preinstall` to verify system requirements
4. Authenticates to the Edera registry with your license key
5. Runs the installer container

The machine reboots when installation completes.

## Options

| Flag | Description |
| --- | --- |
| `--verbose`, `-v` | Show full output from edera-check and the installer |

## Supported platforms

Tested on AWS EC2 in UEFI boot mode:

- Ubuntu 24.04 LTS (Docker)
- Amazon Linux 2023 (Docker)
- CentOS Stream 9 (Podman)
- RHEL 10 (Podman)

## Requirements

- UEFI boot mode
- Docker (Ubuntu, AL2023) or Podman (CentOS, RHEL) installed and accessible without sudo
- `EDERA_LICENSE_KEY` environment variable set

## Security

This script runs the Edera installer container with elevated privileges (`--privileged`, `--pid=host`, `--net=host`, `/` mounted to `/host`). These are required to modify the bootloader and install kernel components. Review [`scripts/install.sh`](scripts/install.sh) before running.

See [`SECURITY.md`](../../SECURITY.md) for the project security policy.
