#!/usr/bin/env bash
set -euo pipefail

INSTANCE_NAME="ederaon-test"
KEEP_SG=false
REGION=""

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' DIM='' RESET=''
fi

header() { printf "\n${BOLD}==> %s${RESET}\n\n" "$*"; }
ok()     { printf "    ${GREEN}✓${RESET}  %s\n" "$*"; }
warn()   { printf "    ${YELLOW}!${RESET}  %s\n" "$*"; }
err()    { printf "${RED}error:${RESET} %s\n" "$*" >&2; }
detail() { printf "    ${DIM}>  %s${RESET}\n" "$*"; }

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 [--name NAME] [--keep-sg] [--region REGION]

Options:
  --name       Instance name tag to tear down (default: ederaon-test)
  --keep-sg    Skip deleting the associated security group
  --region     AWS region (default: your configured AWS profile region)
EOF
    exit 1
}

# ── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)    INSTANCE_NAME="$2"; shift 2 ;;
        --keep-sg) KEEP_SG=true;      shift ;;
        --region)  REGION="$2";       shift 2 ;;
        -h|--help) usage ;;
        *)
            err "unknown option: $1"
            usage
            ;;
    esac
done

SG_NAME="${INSTANCE_NAME}-sg"

# ── Credentials ───────────────────────────────────────────────────────────────
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

# ── Terminate instance ────────────────────────────────────────────────────────
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

# ── Clean up ──────────────────────────────────────────────────────────────────
if [[ "$KEEP_SG" == false ]]; then
    header "Cleaning up"

    printf "    ${DIM}Waiting for instance to terminate...${RESET}\n"
    aws ec2 wait instance-terminated \
        --instance-ids "$INSTANCE_ID"
    ok "Instance terminated"

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query "SecurityGroups[0].GroupId" \
        --output text)

    if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
        read -r -p "    Delete security group '${SG_NAME}' (${SG_ID})? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            aws ec2 delete-security-group \
                --group-id "$SG_ID"
            ok "Security group deleted: ${SG_ID}"
        else
            ok "Security group kept: ${SG_ID}"
        fi
    else
        warn "security group '${SG_NAME}' not found, skipping"
    fi
fi

printf "\n${GREEN}${BOLD}Done.${RESET}\n\n"
