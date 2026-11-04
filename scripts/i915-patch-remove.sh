#!/bin/bash
# Removes the i915 patch and goes back to the stock i915 of each kernel. Reboot afterwards.
#   i915-patch-remove          removes the patched modules from ALL kernels and DISABLES the automation
#                              (re-enable it by running scripts/install.sh again)
#   i915-patch-remove --all    also uninstalls the kernel hook, the boot service and the scripts (except this one);
#                              /var/lib/i915-patch/disabled and the log are kept
# Only modules installed by this tool are removed (those with an ownership marker in /var/lib/i915-patch);
# set FORCE_ALL=1 to remove every /lib/modules/*/updates/i915.ko regardless.
# depmod is run for EACH kernel whose override is removed, not only for the running one.
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)"; exit 1; }
mkdir -p /var/lib/i915-patch
touch /var/lib/i915-patch/disabled          # so that no running or future rebuild reinstalls it
systemctl stop 'i915-patch-build-*.service' i915-patch-catchup.service 2>/dev/null || true
systemctl reset-failed 'i915-patch-build-*.service' 2>/dev/null || true
exec 9>/var/lib/i915-patch/lock; flock -w 120 9 || echo "WARNING: a rebuild is still running; continuing anyway"
shopt -s nullglob
found=0; skipped=0
for f in /lib/modules/*/updates/i915.ko /lib/modules/*/updates/i915.ko.new; do
  kv=$(basename "$(dirname "$(dirname "$f")")")
  if [ "${FORCE_ALL:-0}" != 1 ] && [ ! -f "/var/lib/i915-patch/built-$kv" ] && [ "${f##*.}" != new ]; then
    echo "SKIPPED $f (not installed by this tool; set FORCE_ALL=1 to remove it too)"; skipped=1; continue
  fi
  rm -v "$f"
  [ "${f##*.}" = new ] || rm -f "/var/lib/i915-patch/built-$kv"     # the ownership marker goes with the module
  depmod -a "$kv" || echo "WARNING: depmod failed for $kv"
  echo "$kv: i915 now resolves to: $(modinfo -k "$kv" -n i915)"
  found=1
done
[ "$found" = 1 ] || { [ "$skipped" = 1 ] || echo "No override was installed."; depmod -a "$(uname -r)"; }
sync
if [ "$skipped" = 1 ]; then
  echo "WARNING: at least one /lib/modules/*/updates/i915.ko was NOT removed because this tool did not install it."
  echo "         If it is yours, run: sudo FORCE_ALL=1 i915-patch-remove"
fi
if [ "${1:-}" = "--all" ]; then
  systemctl disable --now i915-patch-catchup.service 2>/dev/null || true
  rm -fv /etc/systemd/system/i915-patch-catchup.service /etc/kernel/postinst.d/zz-i915-patch /usr/local/sbin/i915-patch-rebuild /usr/local/sbin/i915-patch-status
  systemctl daemon-reload 2>/dev/null || true
  rm -rfv --one-file-system -- /usr/local/share/i915-patch /var/cache/i915-patch
  rm -fv /var/lib/i915-patch/*-i915.ko /var/lib/i915-patch/status-* /var/lib/i915-patch/built-*
  echo "Automatic rebuild uninstalled. (/var/lib/i915-patch/disabled, the lock file and /var/log/i915-patch.log are kept.)"
  echo "This script (/usr/local/sbin/i915-patch-remove) stays so you can still use it."
else
  echo "Automatic rebuild is now DISABLED (/var/lib/i915-patch/disabled exists)."
  echo "To re-enable it run scripts/install.sh again; to remove it completely: sudo i915-patch-remove --all"
fi
echo "Done. Reboot, then check that 'modinfo -n i915' prints a path under .../kernel/drivers/gpu/drm/i915/ (not .../updates/)."
