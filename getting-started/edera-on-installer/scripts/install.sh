#!/usr/bin/env bash
set -euo pipefail

INSTALLER_IMAGE="images.edera.dev/installer:on-preview"
EDERA_REGISTRY="images.edera.dev"
VERBOSE=false
ASSUME_YES=false

# ── Colors ────────────────────────────────────────────────────────────────────
setup_colors() {
    if [[ -t 1 ]]; then
        RED=$'\033[0;31m'
        GREEN=$'\033[0;32m'
        YELLOW=$'\033[1;33m'
        BOLD=$'\033[1m'
        DIM=$'\033[2m'
        RESET=$'\033[0m'
    else
        RED='' GREEN='' YELLOW='' BOLD='' DIM='' RESET=''
    fi
}

header() { printf "\n${BOLD}==> %s${RESET}\n\n" "$*"; }
ok()     { printf "    ${GREEN}✓${RESET}  %s\n" "$*"; }
warn()   { printf "    ${YELLOW}!${RESET}  %s\n" "$*"; }
err()    { printf "${RED}error:${RESET} %s\n" "$*" >&2; }
detail() { printf "    ${DIM}>  %s${RESET}\n" "$*" >&2; }

# ── Args ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: EDERA_LICENSE_KEY=<key> install.sh [options]

Installs Edera, a type-1 hypervisor, on this system. Reboots when complete.

Options:
  -y, --yes       Skip the confirmation prompt
  -v, --verbose   Show detailed output from container runs
  -h, --help      Show this help

Get a license key at https://on.edera.dev/
EOF
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --verbose|-v) VERBOSE=true ;;
            --yes|-y)     ASSUME_YES=true ;;
            --help|-h)    usage; exit 0 ;;
            *) err "unknown option: $arg"; exit 1 ;;
        esac
    done
}

# ── Preamble & confirmation ───────────────────────────────────────────────────
show_preamble() {
    cat <<EOF

${BOLD}EderaOn installer${RESET}

This installer will convert this host into an Edera-managed system by:

  * Modifying the bootloader to boot the Edera hypervisor
  * Installing the Edera hypervisor
  * Rebooting the system when the install completes

After reboot, the current OS will run as a guest of the Edera hypervisor.

Supported systems: Ubuntu 24, Amazon Linux 2023, CentOS 9, RHEL 10
Requires: UEFI boot, Docker (Ubuntu/Amazon) or Podman (RHEL/CentOS),
          and a valid Edera license key.

For more information: https://on.edera.dev/

EOF
}

confirm() {
    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi

    local reply
    if [[ -t 0 ]]; then
        printf "Proceed with installation? [y/N] "
        read -r reply
    elif [[ -r /dev/tty ]]; then
        # stdin is piped (e.g. curl | bash); prompt via the controlling tty.
        printf "Proceed with installation? [y/N] "
        read -r reply < /dev/tty
    else
        err "cannot prompt for confirmation — no tty available"
        err "re-run with --yes to proceed non-interactively"
        exit 1
    fi

    case "$reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) printf "Installation cancelled.\n"; exit 0 ;;
    esac
}

# ── License key ───────────────────────────────────────────────────────────────
check_license_key() {
    if [[ -z "${EDERA_LICENSE_KEY:-}" ]]; then
        err "EDERA_LICENSE_KEY is not set"
        printf "    Usage: EDERA_LICENSE_KEY=<your-key> %s\n" "$0"
        printf "    Get a key at https://on.edera.dev/\n"
        exit 1
    fi
}

# OS detection
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        err "cannot detect OS (/etc/os-release not found)"
        exit 1
    fi

    source /etc/os-release
    case "${ID:-}" in
        ubuntu|amzn)
            RUNTIME="docker"
            PRIV_RUN="docker"
            ;;
        centos|rhel)
            RUNTIME="podman"
            PRIV_RUN="sudo podman"
            ;;
        *)
            err "unsupported OS: ${PRETTY_NAME:-$ID}"
            printf "    Supported: Ubuntu 24, Amazon Linux 2023, CentOS 9, RHEL 10\n"
            exit 1
            ;;
    esac

    ok "OS: ${PRETTY_NAME:-$ID}"
    ok "Runtime: $RUNTIME"
}

check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        err "UEFI boot required — this system is using BIOS"
        exit 1
    fi
    ok "Boot: UEFI"
}

check_runtime() {
    if ! command -v "$RUNTIME" &>/dev/null; then
        err "$RUNTIME is not installed — this is required to run the installer"
        exit 1
    fi

    local runtime_err
    if ! runtime_err=$("$RUNTIME" info 2>&1 >/dev/null); then
        err "cannot run $RUNTIME — ensure $USER has permission to use $RUNTIME without sudo"
        [[ -n "$runtime_err" ]] && detail "$runtime_err"
        if [[ "$RUNTIME" == "docker" ]]; then
            printf "    Add your user to the docker group and start a new session:\n"
            printf "      sudo usermod -aG docker \$USER\n"
        fi
        exit 1
    fi
    ok "$RUNTIME is accessible"
}

# Pre-install check
run_preinstall_check() {
    header "Running pre-install checks"

    local tmpfile
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT

    if [[ "$VERBOSE" == true ]]; then
        if ! $PRIV_RUN run --pull always --privileged --pid=host \
            ghcr.io/edera-dev/edera-check:stable preinstall 2>&1 | tee "$tmpfile"; then
            err "edera-check failed to run"
            exit 1
        fi
    else
        if ! $PRIV_RUN run --pull always --privileged --pid=host \
            ghcr.io/edera-dev/edera-check:stable preinstall 2>/dev/null | tee "$tmpfile"; then
            err "edera-check failed to run"
            exit 1
        fi
    fi

    if grep "^\[!\].*Failed" "$tmpfile" | grep -qv "\[Optional\]"; then
        grep "^\[!\].*Failed" "$tmpfile" | grep -v "\[Optional\]" | while IFS= read -r line; do
            warn "$line"
        done
        err "required pre-install checks failed — resolve before installing"
        exit 1
    fi
    ok "All required checks passed"
}

# Registry login
registry_login() {
    header "Authenticating"

    local login_err
    if ! login_err=$($PRIV_RUN login -u license -p "$EDERA_LICENSE_KEY" "$EDERA_REGISTRY" 2>&1 >/dev/null); then
        err "authentication failed — check your license key at https://on.edera.dev/"
        [[ -n "$login_err" ]] && detail "$login_err"
        exit 1
    fi
    ok "Authenticated to $EDERA_REGISTRY"
}

# Run installer
run_installer() {
    header "Installing Edera"

    printf "    The system will reboot when the installer completes.\n\n"

    if [[ "$VERBOSE" == true ]]; then
        $PRIV_RUN run --rm --privileged --pid=host --net=host \
            --env 'TARGET_DIR=/host' \
            --env "EDERA_LICENSE_KEY=${EDERA_LICENSE_KEY}" \
            --volume '/:/host' \
            "$INSTALLER_IMAGE"
    else
        if ! $PRIV_RUN run --rm --privileged --pid=host --net=host \
            --env 'TARGET_DIR=/host' \
            --env "EDERA_LICENSE_KEY=${EDERA_LICENSE_KEY}" \
            --volume '/:/host' \
            "$INSTALLER_IMAGE" > /dev/null 2>&1; then
            err "installer failed — re-run with --verbose for details"
            exit 1
        fi
    fi
}

# main
main() {
    setup_colors
    parse_args "$@"
    check_license_key

    show_preamble
    confirm

    header "Checking system requirements"
    detect_os
    check_uefi
    check_runtime

    run_preinstall_check
    registry_login
    run_installer
}

main "$@"
