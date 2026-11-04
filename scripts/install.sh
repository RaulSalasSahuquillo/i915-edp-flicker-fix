#!/bin/bash
# Installs the tools for the i915 eDP flicker workaround:
#   /usr/local/sbin/i915-patch-{rebuild,status,remove}, the patch, and (unless --no-auto) AUTOMATION:
#   - a kernel postinst hook (/etc/kernel/postinst.d/zz-i915-patch): when a new *-generic kernel is installed it starts
#     i915-patch-rebuild in the background (downloads ~260 MB of kernel source, builds, validates, installs);
#   - a boot-time service (i915-patch-catchup.service): retries for the NEWEST kernel if it has no override yet.
# It does NOT build a module by itself: afterwards run `sudo i915-patch-rebuild` for the running kernel.
#
# Usage: sudo bash scripts/install.sh [--yes] [--no-auto]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
YES=0; AUTO=1
for a in "$@"; do case "$a" in --yes) YES=1;; --no-auto) AUTO=0;; *) echo "unknown option: $a" >&2; exit 2;; esac; done
fail() { echo "ABORT: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail "run as root (sudo)"

for f in i915-patch-rebuild.sh i915-patch-hook.sh i915-patch-status.sh i915-patch-remove.sh i915-ignore-interlane-align-edp.patch; do
  [ -f "$HERE/$f" ] || fail "missing $HERE/$f"
done
for f in i915-patch-rebuild.sh i915-patch-status.sh i915-patch-remove.sh install.sh; do bash -n "$HERE/$f" || fail "syntax error (bash) in $f"; done
sh -n "$HERE/i915-patch-hook.sh" || fail "syntax error (sh/dash) in the hook"   # the hook runs under sh, not bash
for c in python3 flock patch make gcc strip tar gzip dpkg-query apt-get modinfo modprobe depmod od sync systemd-run lsinitramfs; do
  command -v "$c" >/dev/null || fail "missing tool '$c' (on Ubuntu: sudo apt install build-essential python3 patch util-linux kmod initramfs-tools)"
done

# --- Scope: refuse on machines this was never meant for ---
( . /etc/os-release; [ "${ID:-}" = ubuntu ] ) || fail "only tested on Ubuntu (the rebuild uses apt-get source from the Ubuntu archive)"
[ "$(uname -m)" = x86_64 ] || fail "x86_64 only"
edp=0
for c in /sys/class/drm/card*-eDP-*; do
  b=${c##*/}; card=${b%%-*}                      # e.g. card2-eDP-1 -> card2
  [ -e "/sys/class/drm/$card/device/driver" ] && [ "$(basename "$(readlink -f "/sys/class/drm/$card/device/driver")")" = i915 ] && edp=1
done
[ "$edp" = 1 ] || fail "no eDP panel driven by i915 was found: this workaround is not for this machine"
SB=$(od -An -tu1 -j4 -N1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | tr -d ' ' || true)
if grep -qE '\[(integrity|confidentiality)\]' /sys/kernel/security/lockdown 2>/dev/null || [ "$SB" = 1 ]; then
  fail "Secure Boot / kernel lockdown is active: an unsigned i915 would not load and you would be left without the graphics driver. Disable Secure Boot, or do not use this workaround."
fi
[ -r "/boot/initrd.img-$(uname -r)" ] || echo "WARNING: cannot read /boot/initrd.img-$(uname -r); could not check whether i915 is inside the initramfs"
if lsinitramfs "/boot/initrd.img-$(uname -r)" 2>/dev/null | grep 'drivers/gpu/drm/i915/i915\.ko' >/dev/null; then
  fail "i915 is inside your initramfs, where the override would NOT be used (and rebuilding the initramfs is not handled/tested by this tool)"
fi
K0=$(uname -r)
for p in "linux-headers-$K0" "linux-headers-${K0%-generic}"; do
  [ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null || echo none)" = installed ] \
    || echo "WARNING: package $p is not installed. Install it with: sudo apt install linux-headers-$K0"
done

# --- Explicit confirmation ---
cat <<EOF

This will install a workaround that:
  * ignores the DPCD bit INTERLANE_ALIGN_DONE on ALL eDP panels (it hides a real link problem if you have one);
  * builds and installs an UNSIGNED i915 kernel module as root, for the running kernel (when you run i915-patch-rebuild)$( [ "$AUTO" = 1 ] && echo " and, automatically and unattended,
    for every new -generic kernel (~260 MB download + build in the background)" );
  * only makes sense if diagnose/diagnose.sh printed THE SIGNATURE MATCHES for a flickering boot.
A bad module can leave you without the graphics driver (recovery: see README). Tested on one machine only.

EOF
if [ "$YES" != 1 ]; then
  read -r -p "Type YES to continue: " ans || ans=""
  [ "$ans" = YES ] || fail "cancelled (type YES at the prompt, or pass --yes for non-interactive use)"
fi

install -d -m 0755 /usr/local/share/i915-patch /var/lib/i915-patch /var/cache/i915-patch
install -m 0644 "$HERE/i915-ignore-interlane-align-edp.patch" /usr/local/share/i915-patch/i915-ignore-interlane-align-edp.patch
install -m 0755 "$HERE/i915-patch-rebuild.sh" /usr/local/sbin/i915-patch-rebuild
install -m 0755 "$HERE/i915-patch-status.sh"  /usr/local/sbin/i915-patch-status
install -m 0755 "$HERE/i915-patch-remove.sh"  /usr/local/sbin/i915-patch-remove

if [ "$AUTO" = 1 ]; then
  install -m 0755 "$HERE/i915-patch-hook.sh" /etc/kernel/postinst.d/zz-i915-patch
  cat > /etc/systemd/system/i915-patch-catchup.service <<'EOF'
[Unit]
Description=Rebuild the patched i915 for the running kernel if it is missing
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/i915-patch/disabled
ConditionPathExists=!/lib/modules/%v/updates/i915.ko

[Service]
Type=exec
Environment=I915_PATCH_CATCHUP=1
Nice=19
IOSchedulingClass=idle
RuntimeMaxSec=3h
ExecStart=/usr/local/sbin/i915-patch-rebuild %v

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 /etc/systemd/system/i915-patch-catchup.service
  systemctl daemon-reload
  systemctl enable i915-patch-catchup.service >/dev/null 2>&1 || echo "WARNING: could not enable the boot-retry service"
fi

if [ -e /var/lib/i915-patch/disabled ]; then rm -f /var/lib/i915-patch/disabled; echo "NOTE: automation was disabled and is now ENABLED again."; fi

echo
echo "OK: tools installed$( [ "$AUTO" = 1 ] || echo " (no automation: --no-auto)" )."
echo
echo "Next:   sudo i915-patch-rebuild     # build + validate + install for the RUNNING kernel (~260 MB download)"
echo "Then:   i915-patch-status           # BEFORE rebooting: your kernel must say PATCHED"
echo
echo "  Status of every kernel:             i915-patch-status"
echo "  Log:                                /var/log/i915-patch.log"
echo "  Remove the patches and disable:     sudo i915-patch-remove          (then reboot)"
echo "  Uninstall everything:               sudo i915-patch-remove --all"
