#!/usr/bin/env bash
set -euo pipefail

INSTANCE_NAME="ederaon-test"
OS=""
KEY_NAME=""
REGION=""
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

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 [--name NAME] [--os OS] [--key-name KEY_NAME] [--region REGION] [--yes] [--verbose]

Options:
  --name       Instance name tag (default: ederaon-test); security group will be <name>-sg
  --os         OS to use (default: ubuntu24)
               ubuntu24   Ubuntu 24.04 LTS
               al2023     Amazon Linux 2023
               centos9    CentOS Stream 9
               rhel10     Red Hat Enterprise Linux 10
  --key-name   AWS key pair name (default: edera-key)
  --region     AWS region (default: your configured AWS profile region)
  -y, --yes    Skip confirmation prompts
  --verbose    Show full output from dependency installation
EOF
}

# ── Args ──────────────────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)         INSTANCE_NAME="$2"; shift 2 ;;
            --os)           OS="$2";            shift 2 ;;
            --key-name)     KEY_NAME="$2";      shift 2 ;;
            --region)       REGION="$2";        shift 2 ;;
            --verbose|-v)   VERBOSE=true;       shift ;;
            --yes|-y)       ASSUME_YES=true;    shift ;;
            -h|--help)      usage; exit 0 ;;
            *)
                err "unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ── OS config ─────────────────────────────────────────────────────────────────
configure_os() {
    AMI_BOOT_FILTER=()

    case "$OS" in
        ubuntu24)
            AMI_OWNER="099720109477"
            AMI_FILTER="ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
            SSH_USER="ubuntu"
            RUNTIME="docker"
            ;;
        al2023)
            AMI_OWNER="amazon"
            AMI_FILTER="al2023-ami-2023*-x86_64"
            SSH_USER="ec2-user"
            RUNTIME="docker"
            ;;
        centos9)
            AMI_OWNER="679593333241"
            AMI_FILTER="CentOS-Stream-9-*x86_64*"
            SSH_USER="ec2-user"
            RUNTIME="podman"
            AMI_BOOT_FILTER=("Name=boot-mode,Values=uefi,uefi-preferred")
            ;;
        rhel10)
            AMI_OWNER="309956199498"
            AMI_FILTER="RHEL-10*HVM*x86_64*"
            SSH_USER="ec2-user"
            RUNTIME="podman"
            AMI_BOOT_FILTER=("Name=boot-mode,Values=uefi,uefi-preferred")
            ;;
        *)
            err "unknown OS: ${OS}"
            detail "valid options: ubuntu24, al2023, centos9, rhel10"
            exit 1
            ;;
    esac
}

# ── Preamble & confirmation ───────────────────────────────────────────────────
show_preamble() {
    local region_display="${EFFECTIVE_REGION}"
    cat <<EOF

${BOLD}EderaOn EC2 setup${RESET}

This script prepares an EC2 instance to use with EderaON by:

  * Launching an m5.large instance (OS: ${OS}, region: ${region_display})
  * Creating security group ${SG_NAME} with SSH access from your current IP
  * Optionally installing ${RUNTIME} and nftables on the instance

For more information: https://on.edera.dev/prepare-your-vm/

EOF
}

prompt() {
    local msg="$1"
    local always="${2:-}"
    if [[ "$ASSUME_YES" == true && "$always" != "always" ]]; then
        return 0
    fi
    local reply
    if [[ -t 0 ]]; then
        printf "%s [y/N] " "$msg"
        read -r reply
    elif [[ -r /dev/tty ]]; then
        printf "%s [y/N] " "$msg"
        read -r reply < /dev/tty
    else
        return 1
    fi
    case "$reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

confirm() {
    if ! prompt "Proceed with setup?"; then
        printf "Setup cancelled.\n"
        exit 0
    fi
}

# ── Credentials ───────────────────────────────────────────────────────────────
check_credentials() {
    header "Checking credentials"

    if [[ -n "$REGION" ]]; then
        export AWS_DEFAULT_REGION="$REGION"
    fi

    if ! command -v aws &>/dev/null; then
        err "AWS CLI not found"
        detail "install it from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi

    if ! AUTH_CHECK=$(aws sts get-caller-identity 2>&1); then
        err "AWS credentials check failed:"
        detail "${AUTH_CHECK}"
        exit 1
    fi

    EFFECTIVE_REGION="${REGION:-$(aws configure get region 2>/dev/null || echo "")}"
    if [[ -z "$EFFECTIVE_REGION" ]]; then
        err "no AWS region configured — set a default with 'aws configure' or pass --region"
        exit 1
    fi

    ok "Credentials valid"
    ok "Region: ${EFFECTIVE_REGION}"
}

# ── Key file detection ────────────────────────────────────────────────────────
resolve_key_file() {
    KEY_FILE=""
    if [[ "$KEY_NAME" == /* || "$KEY_NAME" == ~* || "$KEY_NAME" == ./* ]]; then
        KEY_FILE="${KEY_NAME/#\~/$HOME}"
        KEY_NAME=$(basename "$KEY_FILE")
        KEY_NAME="${KEY_NAME%.*}"
    else
        for candidate in "${HOME}/.ssh/${KEY_NAME}" "${HOME}/.ssh/${KEY_NAME}.pem" "${HOME}/.ssh/${KEY_NAME}.key"; do
            if [[ -f "$candidate" ]]; then
                KEY_FILE="$candidate"
                break
            fi
        done
    fi
}

# ── Key pair ──────────────────────────────────────────────────────────────────
check_key_pair() {
    header "Checking key pair"

    KEY_EXISTS=$(aws ec2 describe-key-pairs \
        --key-names "$KEY_NAME" \
        --query "KeyPairs[0].KeyName" \
        --output text 2>/dev/null || echo "")

    if [[ -n "$KEY_FILE" ]]; then
        if [[ ! -f "$KEY_FILE" ]]; then
            err "key file not found: ${KEY_FILE}"
            exit 1
        fi
        if [[ -z "$KEY_EXISTS" || "$KEY_EXISTS" == "None" ]]; then
            err "key pair '${KEY_NAME}' not found in AWS (region: ${EFFECTIVE_REGION})"
            detail "to import your existing key: aws ec2 import-key-pair --key-name ${KEY_NAME} --public-key-material fileb://<path-to-public-key>"
            exit 1
        fi
        ok "Key pair: ${KEY_NAME} (${KEY_FILE})"
    elif [[ -z "$KEY_EXISTS" || "$KEY_EXISTS" == "None" ]]; then
        NEW_KEY_FILE="${HOME}/.ssh/${KEY_NAME}.pem"
        warn "key pair '${KEY_NAME}' does not exist in AWS (region: ${EFFECTIVE_REGION})"
        if ! prompt "    Create it and save to ${NEW_KEY_FILE}?" always; then
            err "aborted — re-run with --key-name to specify an existing key pair"
            exit 1
        fi
        mkdir -p "$(dirname "$NEW_KEY_FILE")"
        aws ec2 create-key-pair \
            --key-name "$KEY_NAME" \
            --query 'KeyMaterial' \
            --output text > "$NEW_KEY_FILE"
        chmod 400 "$NEW_KEY_FILE"
        KEY_FILE="$NEW_KEY_FILE"
        ok "Key pair created and saved to ${KEY_FILE}"
    else
        if [[ -z "$KEY_FILE" ]]; then
            err "key pair '${KEY_NAME}' exists in AWS but no matching private key found in ~/.ssh/"
            detail "looked for: ~/.ssh/${KEY_NAME}, ~/.ssh/${KEY_NAME}.pem, ~/.ssh/${KEY_NAME}.key"
            detail "re-run with --key-name <path> to specify the full path to your private key"
            exit 1
        fi
        ok "Key pair: ${KEY_NAME} (${KEY_FILE})"
    fi
}

# ── Existing instance check ───────────────────────────────────────────────────
check_existing_instance() {
    EXISTING=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running,pending" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text)

    if [[ "$EXISTING" != "None" && -n "$EXISTING" ]]; then
        err "instance '${INSTANCE_NAME}' already exists (${EXISTING})"
        detail "terminate it before creating a new one, or run ec2-teardown.sh"
        exit 1
    fi
}

# ── Look up resources ─────────────────────────────────────────────────────────
lookup_resources() {
    header "Looking up resources"

    ami_lookup() {
        aws ec2 describe-images \
            --owners "$AMI_OWNER" \
            --filters "Name=name,Values=${AMI_FILTER}" \
                      "Name=state,Values=available" \
                      "$@" \
            --query "sort_by(Images, &CreationDate)[-1].ImageId" \
            --output text
    }

    if [[ ${#AMI_BOOT_FILTER[@]} -gt 0 ]]; then
        AMI_ID=$(ami_lookup "${AMI_BOOT_FILTER[@]}")
        if [[ "$AMI_ID" == "None" || -z "$AMI_ID" ]]; then
            warn "no UEFI AMI found for ${OS}, retrying without boot-mode filter..."
            AMI_ID=$(ami_lookup)
        fi
    else
        AMI_ID=$(ami_lookup)
    fi

    if [[ "$AMI_ID" == "None" || -z "$AMI_ID" ]]; then
        err "no AMI found for '${OS}' in region '${EFFECTIVE_REGION}'"
        exit 1
    fi

    ok "AMI: ${AMI_ID}"

    ROOT_DEVICE=$(aws ec2 describe-images \
        --image-ids "$AMI_ID" \
        --query 'Images[0].RootDeviceName' \
        --output text)

    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text)

    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        err "no default VPC found — check your AWS configuration"
        exit 1
    fi

    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[0].SubnetId" \
        --output text)

    if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
        err "no subnets found in default VPC (${VPC_ID})"
        exit 1
    fi

    ok "VPC: ${VPC_ID} / Subnet: ${SUBNET_ID}"

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
        --query "SecurityGroups[0].GroupId" \
        --output text)

    if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "EderaON evaluation" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text)

        MY_IP=$(curl -s https://checkip.amazonaws.com)
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "${MY_IP}/32" > /dev/null
        ok "Security group created: ${SG_ID} (SSH from ${MY_IP})"
    else
        ok "Security group: ${SG_ID} (existing)"
    fi
}

# ── Launch ────────────────────────────────────────────────────────────────────
launch_instance() {
    header "Launching instance"

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "m5.large" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --associate-public-ip-address \
        --block-device-mappings "[{\"DeviceName\":\"${ROOT_DEVICE}\",\"Ebs\":{\"VolumeSize\":30,\"VolumeType\":\"gp3\"}}]" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
        --query "Instances[0].InstanceId" \
        --output text)

    ok "Instance launched: ${INSTANCE_ID}"
    printf "    ${DIM}Waiting for instance to be ready...${RESET}\n"

    aws ec2 wait instance-running \
        --instance-ids "$INSTANCE_ID"

    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)

    ok "Instance ready: ${PUBLIC_IP}"
}

# ── Dependencies ──────────────────────────────────────────────────────────────
install_dependencies() {
    printf "\n"
    if ! prompt "Install dependencies (${RUNTIME}, nftables) now?"; then
        return 0
    fi

    header "Installing dependencies"

    SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

    printf "    ${DIM}Waiting for SSH to be ready...${RESET}\n"
    until ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 -o BatchMode=yes \
            "${SSH_USER}@${PUBLIC_IP}" true 2>/dev/null; do
        sleep 5
    done
    ok "SSH ready"

    case "$OS" in
        ubuntu24)
            INSTALL_CMD="sudo apt-get update -qq && sudo apt-get install -y docker.io nftables && sudo systemctl start docker"
            ;;
        al2023)
            INSTALL_CMD="sudo dnf install -y docker nftables && sudo systemctl start docker"
            ;;
        centos9|rhel10)
            INSTALL_CMD="sudo dnf install -y podman nftables"
            ;;
    esac

    printf "    ${DIM}Installing ${RUNTIME} and nftables...${RESET}\n"
    if [[ "$VERBOSE" == true ]]; then
        if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${PUBLIC_IP}" "$INSTALL_CMD"; then
            err "dependency installation failed — re-run with --verbose for details"
            exit 1
        fi
    else
        if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${PUBLIC_IP}" "$INSTALL_CMD" &>/dev/null; then
            err "dependency installation failed — re-run with --verbose for details"
            exit 1
        fi
    fi
    ok "${RUNTIME} and nftables installed"

    if [[ "$RUNTIME" == "docker" ]]; then
        if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${PUBLIC_IP}" \
                "sudo usermod -aG docker ${SSH_USER}" &>/dev/null; then
            err "failed to add ${SSH_USER} to docker group"
            exit 1
        fi
        ok "${SSH_USER} added to docker group"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    setup_colors
    parse_args "$@"

    if [[ -z "$OS" ]]; then
        OS="ubuntu24"
        warn "no --os specified, will use '${OS}'"
    fi

    if [[ -z "$KEY_NAME" ]]; then
        KEY_NAME="edera-key"
        warn "no --key-name specified, will use '${KEY_NAME}'"
    fi

    SG_NAME="${INSTANCE_NAME}-sg"
    configure_os
    check_credentials

    show_preamble
    confirm
    resolve_key_file
    check_key_pair
    check_existing_instance
    lookup_resources
    launch_instance
    install_dependencies

    printf "\n${BOLD}Connect with:${RESET}\n"
    printf "    ssh -i %s %s@%s\n\n" "$KEY_FILE" "$SSH_USER" "$PUBLIC_IP"
    printf "${DIM}Next: https://on.edera.dev/install-edera/${RESET}\n\n"
}

main "$@"
