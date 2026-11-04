#!/bin/bash
# Turns on detailed display-driver logging (drm.debug) so a flickering boot can be captured and analysed.
# It changes no behaviour, it only writes much more to the journal. Undo with flicker-debug-off.sh.
#
# It adds ONE drop-in file, /etc/default/grub.d/90-flicker-debug.cfg, and regenerates the GRUB menu (update-grub).
# Side effects until you turn it off: log_buf_len=32M reserves 32 MiB of RAM, and drm.debug=0x106 writes many MB of journal
# per boot. Review the logs before posting them anywhere (they can contain monitor identifiers and your hostname).
# Debian/Ubuntu GRUB only: on other boot loaders add "drm.debug=0x106 log_buf_len=32M" to the kernel command line by hand.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run it with sudo"; exit 1; }
command -v update-grub >/dev/null && [ -d /etc/default/grub.d ] \
  || { echo "This helper is for Debian/Ubuntu GRUB only. Add 'drm.debug=0x106 log_buf_len=32M' to your kernel command line by hand." >&2; exit 1; }

F=/etc/default/grub.d/90-flicker-debug.cfg
cat > "$F" <<'EOF'
# Temporary: screen-flicker diagnosis. Delete this file and run update-grub to remove it.
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT drm.debug=0x106 log_buf_len=32M"
EOF
update-grub
echo
echo "Created $F"
echo "Reboot, then check:  cat /proc/cmdline   (it must contain drm.debug=0x106 log_buf_len=32M)"
echo "When you are done:   sudo bash diagnose/flicker-debug-off.sh   (and reboot)"
