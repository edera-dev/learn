#!/bin/bash
#
# run-demo.sh — Full demo orchestrator
#
# Usage: ./run-demo.sh [runc|edera|both|cleanup]
#   runc    — deploy and demonstrate the runc escape only
#   edera    — deploy and demonstrate Edera isolation only
#   both    — run both back-to-back (default, best for presentations)
#   cleanup — tear everything down
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-both}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# local block device to serve a PersistentVolumeClaim without a CSI
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
DIND_IMG="/opt/dind-store.img"
DIND_DEV="/dev/dind-disk" 
DIND_SIZE="5G"

wait_for_pod() {
  local ns=$1 pod=$2 timeout=${3:-120}
  echo -e "  Waiting for ${ns}/${pod}..."
  kubectl -n "$ns" wait --for=condition=Ready "pod/$pod" --timeout="${timeout}s" 2>/dev/null
}

stream_build() {
  local ns=$1 pod=$2
  # ci-job exits after the build, so -f closes when the container terminates.
  # timeout is a safety net in case something hangs.
  timeout 300 kubectl -n "$ns" logs "$pod" -c ci-job -f 2>/dev/null || true
}

pause() {
  echo ""
  echo -e "${YELLOW}Press Enter to continue...${NC}"
  read -r
}

run_escape() {
  local pod=$1
  # Inline the script over a TTY exec instead of `kubectl cp` + run it.
  kubectl -n tenant-a exec -it "$pod" -c dind -- sh -c "$(cat "$SCRIPT_DIR/scripts/escape-demo.sh")"
}

ensure_dind_block_device() {
  echo -e "${BOLD}Provisioning a block device for Edera's Docker storage...${NC}"
  [ -f "$DIND_IMG" ] || $SUDO truncate -s "$DIND_SIZE" "$DIND_IMG"

  local loop
  loop=$($SUDO losetup -j "$DIND_IMG" | cut -d: -f1 | head -n1)

  # 512 block size for xen blkfront
  [ -n "$loop" ] || loop=$($SUDO losetup -f --show --sector-size 512 "$DIND_IMG")

  $SUDO rm -f "$DIND_DEV"
  $SUDO mknod "$DIND_DEV" b 7 "${loop#/dev/loop}"
  $SUDO blkid "$DIND_DEV" >/dev/null 2>&1 || $SUDO mkfs.ext4 -F -q "$DIND_DEV"
  echo -e "  ${GREEN}${DIND_DEV} → ${loop} (${DIND_SIZE}, ext4, backed by ${DIND_IMG})${NC}"
  echo ""
}

teardown_dind_block_device() {
  local loop
  loop=$($SUDO losetup -j "$DIND_IMG" 2>/dev/null | cut -d: -f1 | head -n1)
  [ -n "$loop" ] && $SUDO losetup -d "$loop" 2>/dev/null || true
  $SUDO rm -f "$DIND_DEV" "$DIND_IMG" 2>/dev/null || true
}

setup_base() {
  echo -e "${BOLD}Setting up base resources...${NC}"
  kubectl apply -f "$SCRIPT_DIR/manifests/00-namespaces.yaml"
  kubectl apply -f "$SCRIPT_DIR/manifests/01-ci-build-source.yaml"
  kubectl apply -f "$SCRIPT_DIR/manifests/02-tenant-b-victim.yaml"
  wait_for_pod tenant-b victim-app
  echo -e "${GREEN}Tenant B (victim) is running${NC}"
  echo ""
}

demo_runc() {
  echo -e "${BOLD}${RED}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${RED}  PART 1: Privileged DinD on runc (DANGEROUS)${NC}"
  echo -e "${BOLD}${RED}═══════════════════════════════════════════════════════${NC}"
  echo ""

  kubectl apply -f "$SCRIPT_DIR/manifests/03-tenant-a-dind-runc.yaml"
  wait_for_pod tenant-a ci-runner-runc

  echo ""
  echo -e "${CYAN}Watch the CI build happen in real time — this is a real docker build:${NC}"
  echo ""
  stream_build tenant-a ci-runner-runc
  echo ""

  pause

  echo -e "${YELLOW}Running escape demonstration from Tenant A's DinD container...${NC}"
  echo ""

  run_escape ci-runner-runc

  echo ""
  echo -e "${RED}The above was a standard runc container with privileged: true.${NC}"
  echo -e "${RED}The CI build was real. The escape was also real.${NC}"
}

demo_edera() {
  echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${GREEN}  PART 2: Same workload on Edera (ISOLATED)${NC}"
  echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════${NC}"
  echo ""

  ensure_dind_block_device
  kubectl apply -f "$SCRIPT_DIR/manifests/05-dind-block-storage.yaml"
  kubectl apply -f "$SCRIPT_DIR/manifests/04-tenant-a-dind-edera.yaml"
  wait_for_pod tenant-a ci-runner-edera 180

  echo ""
  echo -e "${CYAN}Same CI build, same Docker, now inside a VM — watch it run:${NC}"
  echo ""
  stream_build tenant-a ci-runner-edera
  echo ""

  pause

  echo -e "${YELLOW}Running the SAME escape script inside Edera...${NC}"
  echo ""

  run_escape ci-runner-edera
}

cleanup() {
  echo -e "${BOLD}Cleaning up...${NC}"
  kubectl delete -f "$SCRIPT_DIR/manifests/" --ignore-not-found 2>/dev/null || true
  teardown_dind_block_device
  echo -e "${GREEN}Cleanup complete${NC}"
}

case "$MODE" in
  runc)
    setup_base
    demo_runc
    ;;
  edera)
    setup_base
    demo_edera
    ;;
  both)
    setup_base
    demo_runc
    pause
    demo_edera

    # Pull timing numbers from both pods' logs for a side-by-side comparison
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  TIMING COMPARISON${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""

    RUNC_LOGS=$(kubectl -n tenant-a logs ci-runner-runc -c ci-job 2>/dev/null)
    EDERA_LOGS=$(kubectl -n tenant-a logs ci-runner-edera -c ci-job 2>/dev/null)

    get_timing() {
      echo "$1" | grep "$2" | grep -o '[0-9]*s' | head -1 | tr -d 's'
    }

    RUNC_DAEMON=$(get_timing "$RUNC_LOGS" "Docker daemon startup")
    RUNC_BUILD=$(get_timing "$RUNC_LOGS" "Image build")
    RUNC_SMOKE=$(get_timing "$RUNC_LOGS" "Smoke test")
    RUNC_TOTAL=$(get_timing "$RUNC_LOGS" "Total pipeline")

    EDERA_DAEMON=$(get_timing "$EDERA_LOGS" "Docker daemon startup")
    EDERA_BUILD=$(get_timing "$EDERA_LOGS" "Image build")
    EDERA_SMOKE=$(get_timing "$EDERA_LOGS" "Smoke test")
    EDERA_TOTAL=$(get_timing "$EDERA_LOGS" "Total pipeline")

    printf "  %-24s %8s %8s %10s\n" "" "runc" "edera" "overhead"
    printf "  %-24s %8s %8s %10s\n" "────────────────────────" "────────" "────────" "──────────"
    if [ -n "$RUNC_DAEMON" ] && [ -n "$EDERA_DAEMON" ]; then
      printf "  %-24s %7ss %7ss %+9ss\n" "Docker daemon startup" "$RUNC_DAEMON" "$EDERA_DAEMON" "$((EDERA_DAEMON - RUNC_DAEMON))"
    fi
    if [ -n "$RUNC_BUILD" ] && [ -n "$EDERA_BUILD" ]; then
      printf "  %-24s %7ss %7ss %+9ss\n" "Image build" "$RUNC_BUILD" "$EDERA_BUILD" "$((EDERA_BUILD - RUNC_BUILD))"
    fi
    if [ -n "$RUNC_SMOKE" ] && [ -n "$EDERA_SMOKE" ]; then
      printf "  %-24s %7ss %7ss %+9ss\n" "Smoke test" "$RUNC_SMOKE" "$EDERA_SMOKE" "$((EDERA_SMOKE - RUNC_SMOKE))"
    fi
    if [ -n "$RUNC_TOTAL" ] && [ -n "$EDERA_TOTAL" ]; then
      printf "  %-24s %8s %8s %10s\n" "────────────────────────" "────────" "────────" "──────────"
      printf "  ${BOLD}%-24s %7ss %7ss %+9ss${NC}\n" "Total pipeline" "$RUNC_TOTAL" "$EDERA_TOTAL" "$((EDERA_TOTAL - RUNC_TOTAL))"
    fi
    echo ""
    echo -e "${BOLD}${GREEN}Demo complete.${NC}"
    echo -e "Run ${CYAN}$0 cleanup${NC} to tear down."
    ;;
  cleanup)
    cleanup
    ;;
  *)
    echo "Usage: $0 [runc|edera|both|cleanup]"
    exit 1
    ;;
esac
