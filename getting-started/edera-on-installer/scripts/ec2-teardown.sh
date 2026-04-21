#!/usr/bin/env bash
set -euo pipefail

INSTANCE_NAME="ederaon-test"
KEEP_SG=false
REGION=""
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
Usage: $0 [--name NAME] [--keep-sg] [--region REGION] [--yes]

Options:
  --name       Instance name tag to tear down (default: ederaon-test)
  --keep-sg    Skip deleting the associated security group
  --region     AWS region (default: your configured AWS profile region)
  -y, --yes    Skip confirmation prompts
EOF
}

# ── Args ──────────────────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)     INSTANCE_NAME="$2"; shift 2 ;;
            --keep-sg)  KEEP_SG=true;       shift ;;
            --region)   REGION="$2";        shift 2 ;;
            --yes|-y)   ASSUME_YES=true;    shift ;;
            -h|--help)  usage; exit 0 ;;
            *)
                err "unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ── Preamble & confirmation ───────────────────────────────────────────────────
show_preamble() {
    local region_display="${EFFECTIVE_REGION}"
    local sg_line=""
    if [[ "$KEEP_SG" == false ]]; then
        sg_line="  * Deleting security group ${SG_NAME}"$'\n'
    fi
    cat <<EOF

${BOLD}EderaOn EC2 teardown${RESET}

This script will tear down your EderaON evaluation environment by:

  * Terminating EC2 instance ${INSTANCE_NAME} (region: ${region_display})
${sg_line}
EOF
}

prompt() {
    local msg="$1"
    if [[ "$ASSUME_YES" == true ]]; then
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
    if ! prompt "Proceed with teardown?"; then
        printf "Teardown cancelled.\n"
        exit 0
    fi
}

# ── Credentials ───────────────────────────────────────────────────────────────
check_credentials() {
    header "Checking credentials"

    if [[ -n "$REGION" ]]; then
        export AWS_DEFAULT_REGION="$REGION"
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

# ── Terminate instance ────────────────────────────────────────────────────────
terminate_instance() {
    header "Terminating instance"

    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text)

    if [[ "$INSTANCE_ID" == "None" || -z "$INSTANCE_ID" ]]; then
        err "no instance named '${INSTANCE_NAME}' found"
        exit 1
    fi

    aws ec2 terminate-instances \
        --instance-ids "$INSTANCE_ID" > /dev/null

    ok "Terminating: ${INSTANCE_ID}"
}

# ── Security group cleanup ────────────────────────────────────────────────────
cleanup_security_group() {
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query "SecurityGroups[0].GroupId" \
        --output text)

    if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
        warn "security group '${SG_NAME}' not found, skipping"
        return 0
    fi

    if ! prompt "    Delete security group '${SG_NAME}' (${SG_ID})?"; then
        ok "Security group kept: ${SG_ID}"
        return 0
    fi

    header "Removing security group"

    printf "    ${DIM}Waiting for instance to terminate...${RESET}\n"
    aws ec2 wait instance-terminated \
        --instance-ids "$INSTANCE_ID"
    ok "Instance terminated"

    aws ec2 delete-security-group \
        --group-id "$SG_ID" > /dev/null
    ok "Security group deleted: ${SG_ID}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    setup_colors
    parse_args "$@"

    SG_NAME="${INSTANCE_NAME}-sg"

    check_credentials

    show_preamble
    confirm
    terminate_instance

    if [[ "$KEEP_SG" == false ]]; then
        cleanup_security_group
    fi

    printf "\n${GREEN}${BOLD}Done.${RESET}\n\n"
}

main "$@"
